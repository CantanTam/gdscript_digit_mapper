@tool
extends EditorPlugin

const PLUGIN_VERSION = "1.5.8"
const CONFIG_PATH = "user://gdscript_digit_mapper.cfg"
const MENU_NAME = "GDScript Digit Mapper 设置"

const DEFAULT_MAPPING = {
    "1": "y",
    "2": "e",
    "3": "s",
    "4": "i",
    "5": "w",
    "6": "l",
    "7": "q",
    "8": "b",
    "9": "j",
    "0": "r"
}

const DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

var code_edit = null
var digit_popup = null
var digit_rows = []
var digit_popup_visible = false
var digit_selected_index = 0
var digit_info = {}
var digit_items = []
var ignore_next_popup_update = false
var tab_completion_enabled = true

var settings_dialog = null
var mapping_edits = {}
var tab_completion_check = null
var settings_error = null

func _enter_tree() -> void:
    tab_completion_enabled = _load_tab_completion_enabled()
    add_tool_menu_item(MENU_NAME, Callable(self, "_open_settings"))
    set_process(true)
    set_process_input(true)
    call_deferred("_refresh_editor")

func _exit_tree() -> void:
    remove_tool_menu_item(MENU_NAME)
    _destroy_digit_popup()
    _disconnect_editor()
    if is_instance_valid(settings_dialog):
        settings_dialog.queue_free()
    settings_dialog = null

func _process(_delta: float) -> void:
    _refresh_editor()
    if digit_popup_visible and code_edit != null and is_instance_valid(code_edit):
        _position_digit_popup()

func _refresh_editor() -> void:
    var editor = _find_code_edit()
    if editor == code_edit:
        return

    _destroy_digit_popup()
    _disconnect_editor()
    code_edit = editor

    if code_edit == null:
        return

    if not code_edit.text_changed.is_connected(_on_editor_changed):
        code_edit.text_changed.connect(_on_editor_changed)
    if not code_edit.caret_changed.is_connected(_on_editor_changed):
        code_edit.caret_changed.connect(_on_editor_changed)

func _disconnect_editor() -> void:
    if code_edit == null or not is_instance_valid(code_edit):
        code_edit = null
        return

    if code_edit.text_changed.is_connected(_on_editor_changed):
        code_edit.text_changed.disconnect(_on_editor_changed)
    if code_edit.caret_changed.is_connected(_on_editor_changed):
        code_edit.caret_changed.disconnect(_on_editor_changed)
    code_edit = null

func _find_code_edit():
    var script_editor = get_editor_interface().get_script_editor()
    if script_editor == null:
        return null

    var current_editor = script_editor.get_current_editor()
    if current_editor == null:
        return null

    var base_editor = current_editor.get_base_editor()
    if base_editor is CodeEdit:
        return base_editor
    return null

func _on_editor_changed() -> void:
    if ignore_next_popup_update:
        return
    _update_digit_popup()

# -----------------------------------------------------------------------------
# 数字映射：不再使用 CodeEdit 的自动补全队列，而是使用一个轻量的编辑器内
# Overlay。这样不会修改用户文本来“骗过” Godot 的补全过滤，也不会触发刷新循环。
# -----------------------------------------------------------------------------

func _get_mapping_info(mapping) -> Dictionary:
    if code_edit == null or not is_instance_valid(code_edit):
        return {}
    if not code_edit.has_focus():
        return {}

    var line_index = code_edit.get_caret_line()
    var caret = code_edit.get_caret_column()
    var line = code_edit.get_line(line_index)

    if caret <= 0 or caret > line.length():
        return {}

    var start = caret - 1
    while start >= 0:
        var ch = line.substr(start, 1)
        if ch == "." or _is_mapping_char(ch, mapping):
            start -= 1
        else:
            break
    start += 1

    if start >= caret:
        return {}
    if line.substr(start, 1) != ".":
        return {}
    if start == 0 or line.substr(start - 1, 1) != " ":
        return {}

    var sequence = line.substr(start, caret - start)
    if not _valid_sequence(sequence, mapping):
        return {}

    var mapped = _map_sequence(sequence, mapping)

    return {
        "line": line_index,
        "start": start,
        "end": caret,
        "sequence": sequence,
        "mapped": mapped
    }

func _is_mapping_char(ch: String, mapping) -> bool:
    for digit in DIGITS:
        if String(mapping[digit]) == ch:
            return true
    return false

func _valid_sequence(sequence: String, mapping) -> bool:
    if sequence.is_empty() or not sequence.begins_with("."):
        return false

    var has_letter = false
    for i in range(sequence.length()):
        var ch = sequence.substr(i, 1)
        if ch == ".":
            continue
        if not _is_mapping_char(ch, mapping):
            return false
        has_letter = true

    # “ .”本身也显示全部数字候选；所以没有字母也是合法的。
    return true

func _map_sequence(sequence: String, mapping) -> String:
    var reverse = {}
    for digit in DIGITS:
        reverse[String(mapping[digit])] = digit

    var result = ""
    for i in range(sequence.length()):
        var ch = sequence.substr(i, 1)
        # 第一个 . 只是映射触发前缀，不属于最终结果。
        if i == 0 and ch == ".":
            continue
        if ch == ".":
            # 后续的 . 是普通点号，原样保留。
            result += "."
        else:
            result += String(reverse.get(ch, ch))
    return result

func _get_digit_candidates(info: Dictionary) -> Array:
    var sequence = String(info["sequence"])
    # 只有“.”时只是触发前缀，不显示任何候选。
    if sequence == ".":
        return []
    return [String(info["mapped"])]

func _update_digit_popup() -> void:
    if code_edit == null or not is_instance_valid(code_edit):
        _hide_digit_popup()
        return

    var mapping = _load_mapping()
    var error = _mapping_error(mapping)
    if not error.is_empty():
        _hide_digit_popup()
        return

    var info = _get_mapping_info(mapping)
    if info.is_empty():
        _hide_digit_popup()
        return

    var candidates = _get_digit_candidates(info)
    if candidates.is_empty():
        # “ .” 只作为映射模式触发，不显示初始候选；同时关闭 Godot 原生候选。
        code_edit.cancel_code_completion()
        _hide_digit_popup()
        return

    var first_show = not digit_popup_visible
    digit_info = info
    digit_items = candidates
    if digit_selected_index >= candidates.size():
        digit_selected_index = 0

    if first_show:
        digit_selected_index = 0
        # 如果刚刚输入的是触发点号，取消 Godot 原生补全；之后完全由本插件
        # 的 Overlay 管理数字候选，不再调用 update_code_completion_options()。
        code_edit.cancel_code_completion()
        _ensure_digit_popup()

    _rebuild_digit_rows()
    _position_digit_popup()
    digit_popup_visible = true
    digit_popup.visible = true

func _ensure_digit_popup() -> void:
    if is_instance_valid(digit_popup):
        return

    digit_popup = PanelContainer.new()
    digit_popup.name = "GDScriptDigitMapperPopup"
    digit_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
    digit_popup.focus_mode = Control.FOCUS_NONE
    digit_popup.z_index = 1000
    digit_popup.visible = false

    var box = VBoxContainer.new()
    box.name = "Rows"
    box.add_theme_constant_override("separation", 0)
    digit_popup.add_child(box)

    code_edit.add_child(digit_popup)

func _rebuild_digit_rows() -> void:
    if not is_instance_valid(digit_popup):
        return

    var box = digit_popup.get_node("Rows") as VBoxContainer
    for child in box.get_children():
        child.queue_free()
    digit_rows.clear()

    var count = digit_items.size()
    for i in range(count):
        var label = Label.new()
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        label.text = ("→" if i == digit_selected_index else " ") + String(digit_items[i])
        label.custom_minimum_size = Vector2(150, 24)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        box.add_child(label)
        digit_rows.append(label)

    digit_popup.custom_minimum_size = Vector2(150, max(26, count * 24 + 6))
    digit_popup.size = digit_popup.custom_minimum_size

func _position_digit_popup() -> void:
    if not is_instance_valid(digit_popup) or code_edit == null or not is_instance_valid(code_edit):
        return
    if digit_info.is_empty():
        return

    var line_index = int(digit_info["line"])
    var caret = int(digit_info["end"])
    var pos = code_edit.get_pos_at_line_column(line_index, caret)
    if pos.x < 0 or pos.y < 0:
        return

    var popup_pos = Vector2(pos.x, pos.y + 2)
    var max_x = max(0.0, code_edit.size.x - digit_popup.size.x - 4.0)
    var max_y = max(0.0, code_edit.size.y - digit_popup.size.y - 4.0)
    popup_pos.x = clamp(popup_pos.x, 0.0, max_x)
    popup_pos.y = clamp(popup_pos.y, 0.0, max_y)
    digit_popup.position = popup_pos

func _hide_digit_popup() -> void:
    digit_popup_visible = false
    digit_info.clear()
    digit_items.clear()
    digit_selected_index = 0
    if is_instance_valid(digit_popup):
        digit_popup.visible = false

func _destroy_digit_popup() -> void:
    digit_popup_visible = false
    digit_info.clear()
    digit_items.clear()
    digit_selected_index = 0
    if is_instance_valid(digit_popup):
        digit_popup.queue_free()
    digit_popup = null
    digit_rows.clear()

func _cycle_digit_candidate(forward: bool) -> void:
    if not digit_popup_visible or digit_items.is_empty():
        return
    var count = digit_items.size()
    if forward:
        digit_selected_index = (digit_selected_index + 1) % count
    else:
        digit_selected_index = (digit_selected_index - 1 + count) % count
    _rebuild_digit_rows()
    _position_digit_popup()

func _confirm_digit_candidate(use_mapping: bool) -> void:
    if digit_info.is_empty():
        return

    var line_index = int(digit_info["line"])
    var start = int(digit_info["start"])
    var end = int(digit_info["end"])

    var replacement = ""
    if use_mapping:
        if digit_items.is_empty():
            return
        # Space：使用映射结果；触发用的第一个 . 不会插入。
        replacement = String(digit_items[clamp(digit_selected_index, 0, digit_items.size() - 1)])
    else:
        # Enter：原样输入用户实际键入的字符，包括开头的“.”，
        # 然后追加一个空格；不会换行。用户之后再按 Enter 自己决定换行。
        replacement = String(digit_info["sequence"]) + " "

    ignore_next_popup_update = true
    code_edit.begin_complex_operation()
    code_edit.remove_text(line_index, start, line_index, end)
    code_edit.set_caret_line(line_index, false)
    code_edit.set_caret_column(start, false)
    code_edit.insert_text_at_caret(replacement)
    code_edit.end_complex_operation()
    ignore_next_popup_update = false

    _hide_digit_popup()

func _is_enter_key(key: InputEventKey) -> bool:
    return key.keycode == KEY_ENTER \
        or key.keycode == KEY_KP_ENTER \
        or key.key_label == KEY_ENTER \
        or key.key_label == KEY_KP_ENTER \
        or key.physical_keycode == KEY_ENTER \
        or key.physical_keycode == KEY_KP_ENTER \
        or key.unicode == 10 \
        or key.unicode == 13

func _handle_digit_popup_key(key: InputEventKey) -> bool:
    if not digit_popup_visible:
        return false

    if key.keycode == KEY_SPACE \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        _confirm_digit_candidate(true)
        return true

    if key.keycode == KEY_TAB \
    and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        _cycle_digit_candidate(not key.shift_pressed)
        return true

    # Enter：原样保留 .yywr 等触发串，并在末尾追加一个空格；
    # 这里由插件消费 Enter，防止 Godot 同时换行。
    if _is_enter_key(key) \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        _confirm_digit_candidate(false)
        return true

    if (key.keycode == KEY_UP or key.keycode == KEY_DOWN) \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        return true

    if key.keycode == KEY_ESCAPE:
        _hide_digit_popup()
        return true

    return false


# -----------------------------------------------------------------------------
# 补全按键：Tab / Shift+Tab / Enter / Up / Down
# -----------------------------------------------------------------------------

func _input(event) -> void:
    if code_edit == null or not is_instance_valid(code_edit):
        return
    if not code_edit.has_focus():
        if digit_popup_visible:
            _hide_digit_popup()
        return
    if not (event is InputEventKey):
        return

    var key = event as InputEventKey
    if not key.pressed or key.echo:
        return

    # 数字映射候选：Space / Tab / Enter 由插件处理。
    var had_digit_popup = digit_popup_visible
    if had_digit_popup and _handle_digit_popup_key(key):
        get_viewport().set_input_as_handled()
        return
    if had_digit_popup and _is_enter_key(key) \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        get_viewport().set_input_as_handled()
        return

    # 原生 Godot 自动补全：Tab / Shift+Tab 选择，Enter 确认。
    var options = code_edit.get_code_completion_options()
    if options.is_empty():
        return

    var selected = code_edit.get_code_completion_selected_index()

    if tab_completion_enabled and key.keycode == KEY_TAB \
    and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        var count = options.size()
        if selected < 0:
            selected = 0

        var next_index = 0
        if key.shift_pressed:
            next_index = (selected - 1 + count) % count
        else:
            next_index = (selected + 1) % count

        code_edit.set_code_completion_selected_index(next_index)
        get_viewport().set_input_as_handled()
        return

    if (key.keycode == KEY_UP or key.keycode == KEY_DOWN) \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        get_viewport().set_input_as_handled()
        return

    if _is_enter_key(key) \
    and not key.shift_pressed and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
        code_edit.confirm_code_completion(false)
        get_viewport().set_input_as_handled()
        return


# -----------------------------------------------------------------------------
# 设置窗口
# -----------------------------------------------------------------------------

func _open_settings() -> void:
    if not is_instance_valid(settings_dialog):
        _build_settings_dialog()
    _load_settings_into_dialog()
    settings_dialog.popup_centered(Vector2i(500, 560))

func _build_settings_dialog() -> void:
    settings_dialog = AcceptDialog.new()
    settings_dialog.title = MENU_NAME
    settings_dialog.ok_button_text = "保存"
    settings_dialog.confirmed.connect(_save_settings)
    get_editor_interface().get_base_control().add_child(settings_dialog)

    var root = VBoxContainer.new()
    root.add_theme_constant_override("separation", 8)
    settings_dialog.add_child(root)

    var help = Label.new()
    help.text = "数字映射：输入 空格 + . 开始，输入数字映射字母后显示候选。\n例如：  空格.ysee.wr  →  1322.50\n刚输入“.”时不显示初始候选。中间的 . 始终作为普通点号。\n上下箭头不再选择补全，Tab / Shift+Tab 选择。\n映射候选按 Space 输入数字；按 Enter 保留原字符并追加一个空格，不换行；再次按 Enter 才由 Godot 换行。"
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(help)

    root.add_child(HSeparator.new())

    tab_completion_check = CheckButton.new()
    tab_completion_check.text = "开启 Tab / Shift+Tab 选择自动补全"
    tab_completion_check.tooltip_text = "开启后，自动补全弹出时 Tab 选择下一项，Shift+Tab 选择上一项；关闭后 Tab 恢复为 Godot 原来的行为。"
    root.add_child(tab_completion_check)

    root.add_child(HSeparator.new())

    for digit in DIGITS:
        var row = HBoxContainer.new()
        root.add_child(row)

        var label = Label.new()
        label.text = digit + "  ←"
        label.custom_minimum_size = Vector2(50, 0)
        row.add_child(label)

        var edit = LineEdit.new()
        edit.max_length = 1
        edit.custom_minimum_size = Vector2(140, 0)
        edit.placeholder_text = "小写字母"
        edit.text_changed.connect(_on_mapping_edit_changed)
        row.add_child(edit)
        mapping_edits[digit] = edit

    settings_error = Label.new()
    settings_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(settings_error)

func _load_settings_into_dialog() -> void:
    var mapping = _load_mapping()
    for digit in DIGITS:
        var edit = mapping_edits[digit]
        edit.text = String(mapping[digit])
    if is_instance_valid(tab_completion_check):
        tab_completion_check.button_pressed = _load_tab_completion_enabled()
    _validate_dialog()

func _on_mapping_edit_changed(_text: String) -> void:
    _validate_dialog()

func _validate_dialog() -> void:
    if not is_instance_valid(settings_error):
        return

    var values = {}
    for digit in DIGITS:
        values[digit] = String(mapping_edits[digit].text)

    var error = _mapping_error(values)
    if error.is_empty():
        settings_error.text = "✓ 映射没有冲突。"
        settings_dialog.get_ok_button().disabled = false
    else:
        settings_error.text = "错误：" + error
        settings_dialog.get_ok_button().disabled = true

func _save_settings() -> void:
    var values = {}
    for digit in DIGITS:
        values[digit] = String(mapping_edits[digit].text)

    var error = _mapping_error(values)
    if not error.is_empty():
        _validate_dialog()
        return

    var config = ConfigFile.new()
    config.load(CONFIG_PATH)
    for digit in DIGITS:
        config.set_value("mapping", digit, values[digit])

    if is_instance_valid(tab_completion_check):
        tab_completion_enabled = tab_completion_check.button_pressed
    config.set_value("behavior", "tab_completion_enabled", tab_completion_enabled)
    config.save(CONFIG_PATH)

    settings_dialog.hide()
    _update_digit_popup()

# -----------------------------------------------------------------------------
# 配置读写与冲突检查
# -----------------------------------------------------------------------------

func _load_mapping() -> Dictionary:
    var mapping = DEFAULT_MAPPING.duplicate(true)
    var config = ConfigFile.new()
    if config.load(CONFIG_PATH) == OK:
        for digit in DIGITS:
            if config.has_section_key("mapping", digit):
                mapping[digit] = String(config.get_value("mapping", digit))
    return mapping

func _load_tab_completion_enabled() -> bool:
    var config = ConfigFile.new()
    if config.load(CONFIG_PATH) == OK and config.has_section_key("behavior", "tab_completion_enabled"):
        return bool(config.get_value("behavior", "tab_completion_enabled"))
    return true

func _mapping_error(mapping) -> String:
    var seen = {}

    for digit in DIGITS:
        var key = String(mapping.get(digit, ""))
        if key.length() != 1 or not _is_lowercase_ascii(key):
            return "数字 %s 的映射必须是一个小写英文字母。" % digit

        if seen.has(key):
            return "字母 %s 被数字 %s 和 %s 重复使用。" % [key, String(seen[key]), digit]

        seen[key] = digit

    return ""

func _is_lowercase_ascii(value: String) -> bool:
    if value.length() != 1:
        return false
    var code = value.unicode_at(0)
    return code >= 97 and code <= 122
