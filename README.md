# GDScript Digit Mapper

一个用于 **Godot 4.x 内置 GDScript 代码编辑器**的辅助插件。

本插件提供两个主要功能：

* 使用 `Tab / Shift + Tab` 快速选择自动补全候选项。
* 使用 `.` + 自定义字母快速输入数字，减少输入数字时频繁寻找数字键的操作。

---

## 安装

### 1. 下载插件

进入本项目的 GitHub 页面，点击：

**Code → Download ZIP**

下载完成后解压。

### 2. 放入 Godot 项目的 `addons` 文件夹

在你的 Godot 项目文件夹中创建 `addons` 文件夹（如果已经存在，则不需要创建）。

将解压后的插件文件夹放入 `addons` 中。

最终目录结构应该类似：

```text
YourProject/
├── project.godot
└── addons/
    └── gdscript_digit_mapper/
        ├── plugin.cfg
        └── plugin.gd
```

> 注意：`plugin.cfg` 和 `plugin.gd` 必须直接位于 `gdscript_digit_mapper` 文件夹中。

### 3. 在 Godot 中启用插件

打开 Godot 项目，进入：

**项目 → 项目设置 → 插件**

找到：

**GDScript Digit Mapper**

将插件启用即可。

---

# 基本使用

## 1. 使用 Tab 选择自动补全

插件启用后，自动补全候选项可以使用以下快捷键：

| 快捷键           | 功能       |
| ------------- | -------- |
| `Tab`         | 选择下一个候选项 |
| `Shift + Tab` | 选择上一个候选项 |
| `Enter`       | 确认当前候选项  |

原来的 `↑ / ↓` 选择方式不会再被插件用于选择自动补全。

### 开启 / 关闭 Tab 自动补全选择

可以在插件的图形设置界面中开启或关闭该功能：

**工具 → GDScript Digit Mapper 设置**

关闭后：

* `Tab` 不再用于选择自动补全
* `Shift + Tab` 不再用于选择自动补全
* `Tab / Shift + Tab` 恢复 Godot 原来的行为

---

# 2. 数字快速输入

插件可以使用字母代替数字键。

默认映射：

| 字母  |  数字 |
| --- | --: |
| `y` | `1` |
| `e` | `2` |
| `s` | `3` |
| `i` | `4` |
| `w` | `5` |
| `l` | `6` |
| `q` | `7` |
| `b` | `8` |
| `j` | `9` |
| `r` | `0` |

---

## 开始数字映射

数字映射使用：

```text
. + 映射字母
```

但只有在 `.` 前面存在空格时才会触发。

例如：

```text
.yywr
```

会被识别为：

```text
1 1 5 0
```

候选提示显示为：

```text
→1150
```

---

## Space 和 Enter 的区别

这是数字映射最重要的功能。

### 按 Space

按下 `Space` 后，会输入映射后的数字。

例如：

```text
.yywr
```

按 `Space`：

```text
1150
```

开头的 `.` 会被去掉。

---

### 按 Enter

按下 `Enter` 时，不进行数字转换，而是保留原始输入：

```text
.yywr
```

按 `Enter` 后：

```text
.yywr 
```

也就是：

**保留 `.yywr`，并在后面添加一个空格。**

不会直接换行。

之后是否换行由你自己决定。

---

# 连续数字

多个映射字母可以连续输入。

例如：

```text
.eewj
```

对应：

```text
2259
```

按 `Space`：

```text
2259
```

再例如：

```text
.yywr
```

对应：

```text
1150
```

按 `Space`：

```text
1150
```

---

# 小数

映射过程中间出现的 `.` 会被当作普通的小数点。

例如：

```text
.ysee.wr
```

对应：

```text
1322.50
```

按 `Space`：

```text
1322.50
```

只有最开始的 `.` 是数字映射的触发符。

中间的 `.` 不会重新开始映射。

---

# 为什么要求 `.` 前面有空格？

这是为了避免影响正常的 GDScript 代码。

例如：

```gdscript
player.position
a.b
Vector2.ZERO
```

这些正常的成员访问不会触发数字映射。

只有类似：

```text
 .yywr
```

这种以 **空格 + `.`** 开始的输入才会触发。

---

# 修改数字映射

插件提供图形化设置界面。

打开：

**工具 → GDScript Digit Mapper 设置**

可以直接修改：

```text
1 ← y
2 ← e
3 ← s
4 ← i
5 ← w
6 ← l
7 ← q
8 ← b
9 ← j
0 ← r
```

例如可以改成：

```text
1 ← a
2 ← s
3 ← d
...
```

配置修改后会自动保存。

---

# 映射冲突检测

同一个字母不能同时映射到两个不同的数字。

例如：

```text
1 ← y
2 ← y
```

会产生冲突。

插件会在设置界面中提示错误，并阻止保存冲突的配置。

---

# 功能示例

例如输入：

```text
var number = .yywr
```

候选提示：

```text
→1150
```

按 `Space`：

```gdscript
var number = 1150
```

而按 `Enter`：

```gdscript
var number = .yywr 
```

再例如：

```text
.ysee.wr
```

候选：

```text
→1322.50
```

按 `Space`：

```text
1322.50
```

---

# 配置

插件配置会保存下来，包括：

* 数字映射设置
* Tab / Shift + Tab 自动补全选择开关

重新打开 Godot 后会保留之前的设置。

---

# 系统要求

* Godot 4.x
* 使用 Godot 内置 GDScript 编辑器

不需要修改 Godot 本体，也不需要安装额外依赖。

---

# License

请根据项目实际使用的许可证填写，例如：

```text
MIT License
```
