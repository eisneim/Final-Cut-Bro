export const fcpShortcuts = [
  {
    groupKey: '应用程序',
    groupName: '应用程序',
    shortcuts: [
      {
        shortcut: 'Command + H',
        command: '隐藏应用程序',
        action: '隐藏 Final Cut Pro',
      },
      {
        shortcut: 'Option + Command + H',
        command: '隐藏其他应用程序',
        action: '隐藏除 Final Cut Pro 之外的所有应用程序',
      },
      {
        shortcut: 'Option + Command + K',
        command: '键盘自定',
        action: '打开命令编辑器',
      },
      {
        shortcut: 'Command + M',
        command: '最小化',
        action: '最小化 Final Cut Pro',
      },
      {
        shortcut: 'Command + O',
        command: '打开资源库',
        action: '打开现有资源库或新资源库',
      },
      {
        shortcut: 'Command + ,',
        command: '偏好设置',
        action: '打开 Final Cut Pro 的“偏好设置”窗口',
      },
      {
        shortcut: 'Command + Q',
        command: '退出',
        action: '退出 Final Cut Pro',
      },
      {
        shortcut: 'Shift + Command + Z',
        command: '重做更改',
        action: '重做上一个命令',
      },
      {
        shortcut: 'Command + Z',
        command: '撤销更改',
        action: '撤销上一个命令',
      },
    ],
  },
  {
    groupKey: '编辑',
    groupName: '编辑',
    shortcuts: [
      {
        shortcut: 'Control + Option + L',
        command: '调整音量（绝对）',
        action: '将所有所选片段的音频音量调整为特定的 dB 值',
      },
      {
        shortcut: 'Control + L',
        command: '调整音量（相对）',
        action: '使用相同的 dB 值来调整所有所选片段的音频音量',
      },
      {
        shortcut: 'E',
        command: '追加到故事情节',
        action: '将所选部分添加到故事情节的结尾',
      },
      {
        shortcut: 'Control + Shift + Y',
        command: '试演：添加到试演',
        action: '将所选片段添加到试演',
      },
      {
        shortcut: 'Option + Y',
        command: '试演：复制为试演',
        action: '使用时间线片段和该片段（包括应用的效果）的复制版本创建试演',
      },
      {
        shortcut: 'Shift + Command + Y',
        command: '试演：复制原始项',
        action: '复制选定的试演片段，但不包括应用的效果',
      },
      {
        shortcut: 'Shift + Y',
        command: '试演：替换并添加到试演',
        action: '创建试演并使用当前所选部分替换时间线片段',
      },
      {
        shortcut: 'Command + B',
        command: '切割',
        action: '剪切浏览条或播放头位置处的主要故事情节片段（或所选部分）',
      },
      {
        shortcut: 'Shift + Command + B',
        command: '全部切割',
        action: '剪切浏览条或播放头位置的所有片段',
      },
      {
        shortcut: 'Shift + Command + G',
        command: '将片段项分开',
        action: '将所选项拆分为其组件部分',
      },
      {
        shortcut: 'Control + D',
        command: '更改时间长度',
        action: '更改所选部分的时间长度',
      },
      {
        shortcut: 'Control + Shift + T',
        command: '连接默认下三分之一',
        action: '将默认下三分之一连接到主要故事情节',
      },
      {
        shortcut: 'Control + T',
        command: '连接默认字幕',
        action: '将默认字幕连接到主要故事情节',
      },
      {
        shortcut: 'Q',
        command: '连接到主要故事情节',
        action: '将所选内容连接到主要故事情节',
      },
      {
        shortcut: 'Shift + Q',
        command: '连接到主要故事情节  +  反向时序',
        action: '将所选内容连接到主要故事情节，并将所选内容的结束点与浏览条或播放头对齐',
      },
      {
        shortcut: 'Command + C',
        command: '拷贝',
        action: '拷贝所选部分',
      },
      {
        shortcut: 'Command + Y',
        command: '创建试演',
        action: '从所选部分创建试演',
      },
      {
        shortcut: 'Command + G',
        command: '创建故事情节',
        action: '从连接的片段中的所选内容创建故事情节',
      },
      {
        shortcut: 'Command + X',
        command: '剪切',
        action: '剪切所选部分',
      },
      {
        shortcut: '1',
        command: '剪切和切换到检视器角度 1',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 1',
      },
      {
        shortcut: '2',
        command: '剪切和切换到检视器角度 2',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 2',
      },
      {
        shortcut: '3',
        command: '剪切和切换到检视器角度 3',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 3',
      },
      {
        shortcut: '4',
        command: '剪切和切换到检视器角度 4',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 4',
      },
      {
        shortcut: '5',
        command: '剪切和切换到检视器角度 5',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 5',
      },
      {
        shortcut: '6',
        command: '剪切和切换到检视器角度 6',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 6',
      },
      {
        shortcut: '7',
        command: '剪切和切换到检视器角度 7',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 7',
      },
      {
        shortcut: '8',
        command: '剪切和切换到检视器角度 8',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 8',
      },
      {
        shortcut: '9',
        command: '剪切和切换到检视器角度 9',
        action: '将多机位片段剪切并切换到当前倾斜角度组的角度 9',
      },
      {
        shortcut: 'Delete',
        command: '删除',
        action: '删除所选时间线，拒绝浏览器所选内容，或移除直通编辑',
      },
      {
        shortcut: 'Option + Command + Delete',
        command: '仅删除所选部分',
        action: '删除所选部分并将连接片段连接到产生的空隙片段',
      },
      {
        shortcut: 'Shift + Command + A',
        command: '取消选择全部',
        action: '取消选择所有选定项目',
      },
      {
        shortcut: 'Command + D',
        command: '复制',
        action: '复制浏览器所选部分',
      },
      {
        shortcut: 'V',
        command: '启用/停用片段',
        action: '对所选部分启用或停用播放',
      },
      {
        shortcut: 'Control + S',
        command: '展开音频',
        action: '单独查看选定片段的音频和视频',
      },
      {
        shortcut: 'Control + Option + S',
        command: '展开/折叠音频组件',
        action: '在时间线中展开或折叠所选部分的音频组件',
      },
      {
        shortcut: 'Shift + X',
        command: '延长编辑',
        action: '将选定的编辑点延长到浏览条或播放头位置',
      },
      {
        shortcut: 'Shift + Down',
        command: '向下扩展所选部分',
        action: '在浏览器列表视图中，将下一个项目添加到所选内容',
      },
      {
        shortcut: 'Control + Command + Right',
        command: '扩展所选部分到下一个片段',
        action: '在时间线中，将下一个项目添加到所选内容',
      },
      {
        shortcut: 'Shift + Up',
        command: '向上扩展所选部分',
        action: '在浏览器列表视图中，将上一个项目添加到所选内容',
      },
      {
        shortcut: 'Option + Shift + Y',
        command: '最终确定试演',
        action: '叠化试演并将其替换为试演挑选项',
      },
      {
        shortcut: 'W',
        command: '插入',
        action: '在浏览条或播放头位置插入所选内容',
      },
      {
        shortcut: 'Option + F',
        command: '插入/连接静帧',
        action:
          '在时间线的播放头或浏览条位置插入一个静帧，或将一个静帧从事件中的浏览条或播放头位置连接到时间线中的播放头位置',
      },
      {
        shortcut: 'Option + W',
        command: '插入空隙',
        action: '在浏览条或播放头位置插入空隙片段',
      },
      {
        shortcut: 'Option + Command + W',
        command: '插入默认发生器',
        action: '在浏览条或播放头位置插入默认发生器',
      },
      {
        shortcut: 'Option + Command + Up',
        command: '从故事情节中提取',
        action: '从故事情节举出选择并将其连接到产生的空隙片段',
      },
      {
        shortcut: 'Control + -',
        command: '将音量调低 1 dB',
        action: '将音量调低 1 dB',
      },
      {
        shortcut: 'Control + P',
        command: '移动播放头位置',
        action: '通过输入时间码值移动播放头',
      },
      {
        shortcut: 'Option + G',
        command: '新建复合片段',
        action: '创建新的复合片段（如果无选择，创建空复合片段）',
      },
      {
        shortcut: 'Option + ,',
        command: '向左挪动音频子帧',
        action: '将选定的音频编辑点向左挪动 1 个子帧，从而创建拆分编辑',
      },
      {
        shortcut: 'Option + Shift + ,',
        command: '向左挪动音频子帧很多',
        action: '将选定的音频编辑点向左移动 10 个子帧，从而创建拆分编辑',
      },
      {
        shortcut: 'Option + .',
        command: '向右挪动音频子帧',
        action: '将选定的音频编辑点向右移动 1 个子帧，从而创建拆分编辑',
      },
      {
        shortcut: 'Option + Shift + .',
        command: '向右挪动音频子帧很多',
        action: '将选定的音频编辑点向右移动 10 个子帧，从而创建拆分编辑',
      },
      {
        shortcut: 'Option + Down',
        command: '向下挪动',
        action: '在动画编辑器中向下挪动选定关键帧的值',
      },
      {
        shortcut: ',',
        command: '向左挪动',
        action: '将所选部分向左挪动 1 个单位',
      },
      {
        shortcut: 'Shift + ,',
        command: '向左挪动很多',
        action: '将所选部分向左挪动 10 个单位',
      },
      {
        shortcut: '.',
        command: '向右挪动',
        action: '将所选部分向右挪动 1 个单位',
      },
      {
        shortcut: 'Shift + .',
        command: '向右挪动很多',
        action: '将所选部分向右挪动 10 个单位',
      },
      {
        shortcut: 'Option + Up',
        command: '向上挪动',
        action: '将动画编辑器中所选关键帧的值向上挪动',
      },
      {
        shortcut: 'Y',
        command: '打开试演',
        action: '打开选定的试演',
      },
      {
        shortcut: '`',
        command: '覆盖连接',
        action: '临时覆盖所选部分的片段连接',
      },
      {
        shortcut: 'D',
        command: '覆盖',
        action: '在浏览条或播放头位置覆盖',
      },
      {
        shortcut: 'Shift + D',
        command: '覆盖  +  反向时序',
        action: '从浏览条或播放头位置反向覆盖',
      },
      {
        shortcut: 'Option + Command + Down',
        command: '覆盖到主要故事情节',
        action: '在主要故事情节的浏览条或播放头位置覆盖',
      },
      {
        shortcut: 'Option + V',
        command: '粘贴为连接',
        action: '粘贴选择并将其连接到主要故事情节',
      },
      {
        shortcut: 'Command + V',
        command: '在播放头粘贴插入',
        action: '在浏览条或播放头位置插入剪贴板内容',
      },
      {
        shortcut: 'Control + Shift + Left',
        command: '上一个角度',
        action: '切换到多机位片段中的上一个角度',
      },
      {
        shortcut: 'Option + Shift + Right',
        command: '上一个音频角度',
        action: '切换到多机位片段中的上一个音频角度',
      },
      {
        shortcut: 'Control + Left',
        command: '上一个挑选项',
        action: '选择“试演”窗口中的上一个片段，使其成为试演挑选项',
      },
      {
        shortcut: 'Shift + Command + Left',
        command: '上一个视频角度',
        action: '切换到多机位片段中的上一个视频角度',
      },
      {
        shortcut: 'Control + =',
        command: '将音量调高 1 dB',
        action: '将音量调高 1 dB',
      },
      {
        shortcut: 'Shift + R',
        command: '替换',
        action: '使用浏览器中的所选部分来替换时间线中的所选片段',
      },
      {
        shortcut: 'Option + R',
        command: '从开始处替换',
        action: '使用浏览器中的所选部分替换时间线中的所选片段（从其起始点开始）',
      },
      {
        shortcut: 'Shift + Delete',
        command: '替换为空隙',
        action: '使用空隙片段替换所选时间线片段',
      },
      {
        shortcut: 'Command + A',
        command: '全选',
        action: '选择所有片段',
      },
      {
        shortcut: 'C',
        command: '选择片段',
        action: '选择时间线中指针下方的片段',
      },
      {
        shortcut: 'Command + Up',
        command: '选择上方片段',
        action: '选择浏览条或播放头位置的当前时间线所选内容上方的片段',
      },
      {
        shortcut: 'Command + Down',
        command: '选择下方片段',
        action: '选择浏览条或播放头位置的当前时间线所选内容下方的片段',
      },
      {
        shortcut: 'Shift + [',
        command: '选择左音频边缘',
        action: '对于展开视图中的音频/视频片段，选择音频编辑点的左边缘',
      },
      {
        shortcut: '[',
        command: '选择左边缘',
        action: '选择编辑点的左边缘',
      },
      {
        shortcut: 'Shift + \\',
        command: '选择左音频编辑边缘和右音频编辑边缘',
        action: '对于展开视图中的音频/视频片段，选择音频编辑点的左边缘和右边缘',
      },
      {
        shortcut: '\\',
        command: '选择左编辑边缘和右编辑边缘',
        action: '选择编辑点的左边缘和右边缘',
      },
      {
        shortcut: 'Control + \\',
        command: '选择左右视频编辑边缘',
        action: '对于已展开视图中的音频/视频片段，请选择视频编辑点的左边缘和右边缘',
      },
      {
        shortcut: 'Control + [',
        command: '选择左视频边缘',
        action: '对于已展开视图中的音频/视频片段，请选择视频编辑点的左边缘',
      },
      {
        shortcut: 'Control + Shift + Right',
        command: '选择下一个角度',
        action: '切换到多机位片段中的下一个角度',
      },
      {
        shortcut: 'Option + Shift + Right',
        command: '选择下一个音频角度',
        action: '切换到多机位片段中的下一个音频角度',
      },
      {
        shortcut: 'Command + Right',
        command: '选择下一个片段',
        action: '移动播放头和所选内容到角色相同的下一个最顶层时间线片段',
      },
      {
        shortcut: 'Control + Right',
        command: '选择下一个挑选项',
        action: '选择“试演”窗口中的下一个片段，使其成为试演挑选项',
      },
      {
        shortcut: 'Shift + Command + Right',
        command: '选择下一个视频角度',
        action: '切换到多机位片段中的下一个视频角度',
      },
      {
        shortcut: 'Command + Left',
        command: '选择上一个片段',
        action: '移动播放头和所选内容到角色相同的上一个最顶层时间线片段',
      },
      {
        shortcut: 'Shift + ]',
        command: '选择右音频边缘',
        action: '对于展开视图中的音频/视频片段，选择音频编辑点的右边缘',
      },
      {
        shortcut: ']',
        command: '选择右边缘',
        action: '选择编辑点的右边缘',
      },
      {
        shortcut: 'Control + ]',
        command: '选择右视频边缘',
        action: '对于已展开视图中的音频/视频片段，请选择视频编辑点的右边缘',
      },
      {
        shortcut: 'Shift + Command + O',
        command: '设定附加所选部分结尾',
        action: '在播放头或浏览条位置设定附加范围选择结束点',
      },
      {
        shortcut: 'Shift + Command + I',
        command: '设定附加所选部分开头',
        action: '在播放头或浏览条位置设定附加范围选择起始点',
      },
      {
        shortcut: 'Control + E',
        command: '显示/隐藏精确度编辑器',
        action: '选择编辑点时，显示或隐藏精确度编辑器',
      },
      {
        shortcut: 'N',
        command: '吸附',
        action: '打开或关闭吸附',
      },
      {
        shortcut: 'Option + S',
        command: '独奏',
        action: '独奏时间线中的所选项',
      },
      {
        shortcut: 'Shift + 1',
        command: '源媒体：音频和视频',
        action: '打开音频/视频模式以将所选部分的视频和音频部分添加到时间线',
      },
      {
        shortcut: 'Shift + 3',
        command: '源媒体：仅音频',
        action: '打开仅音频模式以将所选部分的音频部分添加到时间线',
      },
      {
        shortcut: 'Shift + 2',
        command: '源媒体：仅视频',
        action: '打开仅视频模式以将所选部分的视频部分添加到时间线',
      },
      {
        shortcut: 'Control + Option + Command + C',
        command: '拆分字幕',
        action: '将所选字幕替换为相邻的单行字幕，代替原始字幕中的每行文本。',
      },
      {
        shortcut: 'Option + 1',
        command: '切换到检视器角度 1',
        action: '将多机位片段切换到当前倾斜角度组的角度 1',
      },
      {
        shortcut: 'Option + 2',
        command: '切换到检视器角度 2',
        action: '将多机位片段切换到当前倾斜角度组的角度 2',
      },
      {
        shortcut: 'Option + 3',
        command: '切换到检视器角度 3',
        action: '将多机位片段切换到当前倾斜角度组的角度 3',
      },
      {
        shortcut: 'Option + 4',
        command: '切换到检视器角度 4',
        action: '将多机位片段切换到当前倾斜角度组的角度 4',
      },
      {
        shortcut: 'Option + 5',
        command: '切换到检视器角度 5',
        action: '将多机位片段切换到当前倾斜角度组的角度 5',
      },
      {
        shortcut: 'Option + 6',
        command: '切换到检视器角度 6',
        action: '将多机位片段切换到当前倾斜角度组的角度 6',
      },
      {
        shortcut: 'Option + 7',
        command: '切换到检视器角度 7',
        action: '将多机位片段切换到当前倾斜角度组的角度 7',
      },
      {
        shortcut: 'Option + 8',
        command: '切换到检视器角度 8',
        action: '将多机位片段切换到当前倾斜角度组的角度 8',
      },
      {
        shortcut: 'Option + 9',
        command: '切换到检视器角度 9',
        action: '将多机位片段切换到当前倾斜角度组的角度 9',
      },
      {
        shortcut: 'G',
        command: '切换故事情节模式',
        action: '打开或关闭在时间线中拖移片段时构建故事情节的功能',
      },
      {
        shortcut: 'Option + ]',
        command: '修剪结尾处',
        action: '将选定或最顶部的片段的结尾处修剪到浏览条或播放头位置',
      },
      {
        shortcut: 'Option + [',
        command: '修剪开始处',
        action: '将片段开始点修剪到浏览条或播放头位置',
      },
      {
        shortcut: 'Option + \\',
        command: '修剪到所选部分',
        action: '将片段开始点和结束点修剪到范围选择',
      },
    ],
  },
  {
    groupKey: '效果',
    groupName: '效果',
    shortcuts: [
      {
        shortcut: 'Control + Shift + T',
        command: '添加基本下三分之一',
        action: '将基本下三分之一字幕连接到主要故事情节',
      },
      {
        shortcut: 'Control + T',
        command: '添加基本字幕',
        action: '将基本字幕连接到主要故事情节',
      },
      {
        shortcut: 'Option + Command + E',
        command: '添加默认音频效果',
        action: '将默认音频效果添加到所选部分',
      },
      {
        shortcut: 'Command + T',
        command: '添加默认转场',
        action: '将默认转场添加到所选部分',
      },
      {
        shortcut: 'Option + T',
        command: '交叉渐变',
        action: '对所选片段之间的音频编辑点应用交叉渐变',
      },
      {
        shortcut: 'Option + E',
        command: '添加默认视频效果',
        action: '将默认视频效果添加到所选部分',
      },
      {
        shortcut: 'Option + Delete',
        command: '颜色板：还原当前板控制',
        action: '还原当前“颜色板”面板中的控制',
      },
      {
        shortcut: 'Control + Command + C',
        command: '颜色板：切换到“颜色”面板',
        action: '切换到颜色板中的“颜色”面板',
      },
      {
        shortcut: 'Control + Command + E',
        command: '颜色板：切换到“曝光”面板',
        action: '切换到颜色板中的“曝光”面板',
      },
      {
        shortcut: 'Control + Command + S',
        command: '颜色板：切换到“饱和度”面板',
        action: '切换到颜色板中的“饱和度”面板',
      },
      {
        shortcut: 'Option + Command + C',
        command: '拷贝效果',
        action: '拷贝选定的效果及其设置',
      },
      {
        shortcut: 'Option + Shift + C',
        command: '拷贝关键帧',
        action: '拷贝所选关键帧及其设置',
      },
      {
        shortcut: 'Option + Shift + X',
        command: '剪切关键帧',
        action: '剪切所选关键帧及其设置',
      },
      {
        shortcut: 'Option + Command + B',
        command: '启用/停用平衡颜色',
        action: '打开或关闭平衡色彩校正',
      },
      {
        shortcut: 'Shift + Command + M',
        command: '匹配音频',
        action: '在片段之间匹配声音',
      },
      {
        shortcut: 'Option + Command + M',
        command: '匹配颜色',
        action: '在片段之间匹配颜色',
      },
      {
        shortcut: 'Option + Tab',
        command: '下一个文本',
        action: '导航到下一个文本项',
      },
      {
        shortcut: 'Shift + Command + V',
        command: '粘贴属性',
        action: '将所选属性及其设置粘贴到所选部分',
      },
      {
        shortcut: 'Option + Command + V',
        command: '粘贴效果',
        action: '将效果及其设置粘贴到所选部分',
      },
      {
        shortcut: 'Option + Shift + V',
        command: '粘贴关键帧',
        action: '将关键帧及其设置粘贴到所选部分',
      },
      {
        shortcut: 'Option + Shift + Tab',
        command: '上一个文本',
        action: '导航到上一个文本项',
      },
      {
        shortcut: 'Shift + Command + X',
        command: '移除属性',
        action: '将选定的属性从所选部分中移除',
      },
      {
        shortcut: 'Option + Command + X',
        command: '移除效果',
        action: '将所有效果从所选部分中移除',
      },
      {
        shortcut: 'Command + R',
        command: '重新定时编辑器',
        action: '显示或隐藏重新定时编辑器',
      },
      {
        shortcut: 'Shift + N',
        command: '重新定时：创建正常速度分段',
        action: '将选择设定为以正常 (100%) 速度播放',
      },
      {
        shortcut: 'Shift + H',
        command: '重新定时：保留',
        action: '创建 2 秒静止分段',
      },
      {
        shortcut: 'Option + Command + R',
        command: '重新定时：还原',
        action: '将选择还原为以正常 (100%) 速度向前播放',
      },
      {
        shortcut: 'Control + Shift + V',
        command: '单独播放动画',
        action: '在视频动画编辑器中一次仅显示一个效果',
      },
    ],
  },
  {
    groupKey: '常规',
    groupName: '常规',
    shortcuts: [
      {
        shortcut: 'Delete',
        command: '删除',
        action: '删除时间线所选内容，拒绝浏览器所选内容，或移除直通编辑',
      },
      {
        shortcut: 'Command + F',
        command: '查找',
        action: '显示或隐藏“过滤器”窗口（浏览器中）或时间线索引（时间线中）',
      },
      {
        shortcut: 'Option + Command + 3',
        command: '前往事件检视器',
        action: '激活事件检视器',
      },
      {
        shortcut: 'Command + I',
        command: '导入媒体',
        action: '从设备、摄像机或归档导入媒体',
      },
      {
        shortcut: 'Control + Command + J',
        command: '资源库属性',
        action: '打开当前资源库的资源库属性检查器',
      },
      {
        shortcut: 'Command + Delete',
        command: '移到废纸篓',
        action: '将所选部分移到“访达”废纸篓',
      },
      {
        shortcut: 'Command + N',
        command: '新建项目',
        action: '创建新项目',
      },
      {
        shortcut: 'Command + J',
        command: '项目属性',
        action: '打开当前项目的属性检查器',
      },
      {
        shortcut: 'Control + Shift + R',
        command: '渲染全部',
        action: '启动当前项目的所有渲染任务',
      },
      {
        shortcut: 'Control + R',
        command: '渲染所选部分',
        action: '开始选择的渲染任务',
      },
      {
        shortcut: 'Shift + Command + R',
        command: '在“访达”中显示',
        action: '在“访达”中显示所选事件片段的源媒体文件',
      },
    ],
  },
  {
    groupKey: '标记',
    groupName: '标记',
    shortcuts: [
      {
        shortcut: 'Option + C',
        command: '添加字幕',
        action: '将字幕添加到播放头位置的活跃语言子角色（如果字幕编辑器已打开，则按下 Control + Option + C）',
      },
      {
        shortcut: 'M',
        command: '添加标记',
        action: '在浏览条或播放头的位置添加标记',
      },
      {
        shortcut: 'Control + C',
        command: '所有片段',
        action: '更改浏览器过滤器设置来显示所有片段',
      },
      {
        shortcut: 'Option + M',
        command: '添加标记并修改',
        action: '添加标记并编辑标记文本',
      },
      {
        shortcut: 'Control + 1',
        command: '应用关键词标记 1',
        action: '将关键词 1 应用到所选部分',
      },
      {
        shortcut: 'Control + 2',
        command: '应用关键词标记 2',
        action: '将关键词 2 应用到所选部分',
      },
      {
        shortcut: 'Control + 3',
        command: '应用关键词标记 3',
        action: '将关键词 3 应用到所选部分',
      },
      {
        shortcut: 'Control + 4',
        command: '应用关键词标记 4',
        action: '将关键词 4 应用到所选部分',
      },
      {
        shortcut: 'Control + 5',
        command: '应用关键词标记 5',
        action: '将关键词 5 应用到所选部分',
      },
      {
        shortcut: 'Control + 6',
        command: '应用关键词标记 6',
        action: '将关键词 6 应用到所选部分',
      },
      {
        shortcut: 'Control + 7',
        command: '应用关键词标记 7',
        action: '将关键词 7 应用到所选部分',
      },
      {
        shortcut: 'Control + 8',
        command: '应用关键词标记 8',
        action: '将关键词 8 应用到所选部分',
      },
      {
        shortcut: 'Control + 9',
        command: '应用关键词标记 9',
        action: '将关键词 9 应用到所选部分',
      },
      {
        shortcut: 'Option + X',
        command: '清除所选范围',
        action: '清除范围选择',
      },
      {
        shortcut: 'Option + O',
        command: '清除范围结尾',
        action: '清除范围的结束点',
      },
      {
        shortcut: 'Option + I',
        command: '清除范围开头',
        action: '清除范围的开始点',
      },
      {
        shortcut: 'Control + M',
        command: '删除标记',
        action: '删除选定的标记',
      },
      {
        shortcut: 'Control + Shift + M',
        command: '删除选择中的标记',
        action: '删除选择中的所有标记',
      },
      {
        shortcut: 'Shift + Command + A',
        command: '取消选择全部',
        action: '取消选择所有选定项目',
      },
      {
        shortcut: 'Control + Shift + C',
        command: '编辑字幕',
        action: '在字幕编辑器中打开所选字幕',
      },
      {
        shortcut: 'F',
        command: '个人收藏',
        action: '将浏览器中的所选部分评为个人收藏',
      },
      {
        shortcut: 'Control + F',
        command: '个人收藏',
        action: '更改浏览器过滤器设置来显示个人收藏',
      },
      {
        shortcut: 'Control + H',
        command: '隐藏被拒绝的项目',
        action: '更改浏览器过滤器设置来隐藏被拒绝的片段',
      },
      {
        shortcut: 'Shift + Command + K',
        command: '新关键词精选',
        action: '创建新的关键词精选',
      },
      {
        shortcut: 'Option + Command + N',
        command: '新智能精选',
        action: '创建新的智能精选',
      },
      {
        shortcut: 'R',
        command: '范围选择工具',
        action: '将“范围选择”工具设为活跃',
      },
      {
        shortcut: 'Delete',
        command: '拒绝',
        action: '将浏览器中的当前所选部分标记为被拒绝的',
      },
      {
        shortcut: 'Control + Delete',
        command: '被拒绝的',
        action: '更改浏览器过滤器设置来显示被拒绝的片段',
      },
      {
        shortcut: 'Control + 0',
        command: '从选择中移除所有关键词',
        action: '将所有关键词从浏览器中的所选部分移除',
      },
      {
        shortcut: 'Control + Option + D',
        command: '角色：应用对白角色',
        action: '将对白子角色应用到所选片段的组件中',
      },
      {
        shortcut: 'Control + Option + E',
        command: '角色：应用效果角色',
        action: '将效果子角色应用到所选片段的组件中',
      },
      {
        shortcut: 'Control + Option + M',
        command: '角色：应用音乐角色',
        action: '将音乐子角色应用到所选片段的组件中',
      },
      {
        shortcut: 'Control + Option + T',
        command: '角色：应用字幕角色',
        action: '将“字幕”角色应用于选定的片段',
      },
      {
        shortcut: 'Control + Option + V',
        command: '角色：应用视频角色',
        action: '将“视频”角色应用于选定的片段',
      },
      {
        shortcut: 'Command + A',
        command: '全选',
        action: '选择所有片段',
      },
      {
        shortcut: 'X',
        command: '选择片段范围',
        action: '设定范围选择以匹配浏览条或播放头下方片段的边界',
      },
      {
        shortcut: 'Shift + Command + O',
        command: '设定附加范围结尾',
        action: '在播放头或浏览条位置设定附加范围选择结束点',
      },
      {
        shortcut: 'Shift + Command + I',
        command: '设定附加范围开头',
        action: '在播放头或浏览条位置设定附加范围选择起始点',
      },
      {
        shortcut: 'O',
        command: '设定范围结尾',
        action: '设定范围的结束点',
      },
      {
        shortcut: 'Control + O',
        command: '设定范围结尾',
        action: '编辑文本栏时设定范围的结束点',
      },
      {
        shortcut: 'I',
        command: '设定范围开头',
        action: '设定范围的开始点',
      },
      {
        shortcut: 'Control + I',
        command: '设定范围开头',
        action: '编辑文本栏时设定范围的开始点',
      },
      {
        shortcut: 'U',
        command: '取消评分',
        action: '从选择中移除评分',
      },
    ],
  },
  {
    groupKey: '整理',
    groupName: '整理',
    shortcuts: [
      {
        shortcut: 'Option + N',
        command: '新建事件',
        action: '创建新事件',
      },
      {
        shortcut: 'Shift + Command + N',
        command: '新建文件夹',
        action: '创建新文件夹',
      },
      {
        shortcut: 'Shift + F',
        command: '在浏览器中显示',
        action: '在浏览器中显示选定的片段',
      },
      {
        shortcut: 'Option + Shift + Command + F',
        command: '在浏览器中显示项目',
        action: '在浏览器中显示打开的项目',
      },
      {
        shortcut: 'Option + Command + G',
        command: '同步片段',
        action: '同步所选事件片段',
      },
    ],
  },
  {
    groupKey: '播放和导航',
    groupName: '播放和导航',
    shortcuts: [
      {
        shortcut: 'Shift + S',
        command: '音频浏览',
        action: '打开或关闭音频浏览',
      },
      {
        shortcut: 'Control + Command + Y',
        command: '试演：预览',
        action: '在时间线的情境中播放挑选',
      },
      {
        shortcut: 'Option + Command + S',
        command: '片段浏览',
        action: '打开或关闭片段浏览',
      },
      {
        shortcut: 'Option + Shift + 3',
        command: '仅剪切/切换多机位音频',
        action: '打开仅音频模式以进行多机位剪切和切换',
      },
      {
        shortcut: 'Option + Shift + 1',
        command: '剪切/切换多机位音频和视频',
        action: '打开音频/视频模式以进行多机位剪切和切换',
      },
      {
        shortcut: 'Option + Shift + 2',
        command: '仅剪切/切换多机位视频',
        action: '打开仅视频模式以进行多机位剪切和切换',
      },
      {
        shortcut: 'Down',
        command: '向下',
        action: '转至下一项（浏览器中）或下一个编辑点（时间线中）',
      },
      {
        shortcut: 'Control + Down',
        command: '向下',
        action: '编辑文本栏时，转至下一项（浏览器中）或下一个编辑点（时间线中）',
      },
      {
        shortcut: 'Shift + Left',
        command: '后退 10 帧',
        action: '将播放头向后移动 10 帧',
      },
      {
        shortcut: 'Shift + Right',
        command: '前进 10 帧',
        action: '将播放头向前移动 10 帧',
      },
      {
        shortcut: 'Home | Fn + Left',
        command: '跳到开头',
        action: '将播放头移到时间线的开始处或浏览器中的第一个片段',
      },
      {
        shortcut: 'End | Fn + Right',
        command: '跳到结尾',
        action: '将播放头移到时间线的结尾处或浏览器中的最后一个片段',
      },
      {
        shortcut: 'Option + Shift + ’',
        command: '跳到下一个倾斜角度组',
        action: '在当前的多机位片段中显示角度的下一个倾斜角度组',
      },
      {
        shortcut: '’',
        command: '跳到下一个编辑点',
        action: '将播放头移到时间线中的下一个编辑点',
      },
      {
        shortcut: 'Option + Right',
        command: '跳到下一栏',
        action: '将播放头移到隔行扫描片段中的下一栏',
      },
      {
        shortcut: 'Right',
        command: '跳到下一帧',
        action: '将播放头移到下一帧',
      },
      {
        shortcut: 'Option + Right',
        command: '跳到下一子帧',
        action: '将播放头移到下一音频子帧',
      },
      {
        shortcut: 'Option + Shift + ;',
        command: '跳到上一个倾斜角度组',
        action: '在当前的多机位片段中显示角度的上一个倾斜角度组',
      },
      {
        shortcut: ';',
        command: '跳到上一个编辑点',
        action: '将播放头移到时间线中的上一个编辑点',
      },
      {
        shortcut: 'Option + Left',
        command: '跳到上一栏',
        action: '将播放头移到隔行扫描片段中的上一栏',
      },
      {
        shortcut: 'Left',
        command: '跳到上一帧',
        action: '将播放头移到上一帧',
      },
      {
        shortcut: 'Option + Left',
        command: '跳到上一子帧',
        action: '将播放头移到上一音频子帧',
      },
      {
        shortcut: 'Shift + O',
        command: '跳到范围结尾',
        action: '将播放头移到范围选择的结尾',
      },
      {
        shortcut: 'Shift + I',
        command: '跳到范围开头',
        action: '将播放头移到范围选择的开始处',
      },
      {
        shortcut: 'Control + Option + Command + ]',
        command: '顺时针方向看',
        action: '顺时针转动 360° 检视器',
      },
      {
        shortcut: 'Control + Option + Command + [',
        command: '逆时针方向看',
        action: '逆时针转动 360° 检视器',
      },
      {
        shortcut: 'Control + Option + Command + Down',
        command: '向下看',
        action: '向下倾斜 360° 检视器',
      },
      {
        shortcut: 'Control + Option + Command + Left',
        command: '向左看',
        action: '向左平移 360° 检视器',
      },
      {
        shortcut: 'Control + Option + Command + Right',
        command: '向右看',
        action: '向右平移 360° 检视器',
      },
      {
        shortcut: 'Control + Option + Command + Up',
        command: '向上看',
        action: '向上平移 360° 检视器',
      },
      {
        shortcut: 'Command + L',
        command: '循环播放',
        action: '打开或关闭循环播放',
      },
      {
        shortcut: 'Control + Option + Command + 9',
        command: '镜像 VR 头显',
        action: '在 360° 检视器中镜像连接的 VR 头显的显示屏',
      },
      {
        shortcut: 'Shift + A',
        command: '监视音频',
        action: '打开或关闭要浏览的角度的音频监视',
      },
      {
        shortcut: '-',
        command: '导航时间码输入',
        action: '输入负时间码值将向后移动播放头、向后移动片段或修剪范围或片段，具体取决于选择',
      },
      {
        shortcut: 'Control + Command + Right',
        command: '下一个片段',
        action: '转至下一项（浏览器中）或下一个编辑点（时间线中）',
      },
      {
        shortcut: 'Control + ’',
        command: '下一个标记',
        action: '将播放头移到下一个标记',
      },
      {
        shortcut: 'Control + Option + Command + 7',
        command: '输出至 VR 头显',
        action: '将 360° 视频发送到连接的 VR 头显',
      },
      {
        shortcut: 'Shift + ?',
        command: '播放当前位置前后片段',
        action: '在播放头位置周围播放',
      },
      {
        shortcut: 'L',
        command: '向前播放',
        action: '向前播放（按下 L 键多次可增加播放速度）',
      },
      {
        shortcut: 'Option + Space',
        command: '从播放头播放',
        action: '从播放头位置播放',
      },
      {
        shortcut: 'Shift + Command + F',
        command: '以全屏幕模式播放',
        action: '从浏览条或播放头位置全屏幕播放',
      },
      {
        shortcut: 'J',
        command: '倒退播放',
        action: '倒退播放（按下 J 键多次可增加倒退播放速度）',
      },
      {
        shortcut: 'Control + J',
        command: '倒退播放',
        action: '编辑文本栏时倒退播放（按下 J 键多次可增加倒退播放速度）',
      },
      {
        shortcut: 'Shift + Space',
        command: '倒退播放',
        action: '倒退播放',
      },
      {
        shortcut: '/',
        command: '播放所选部分',
        action: '播放选择',
      },
      {
        shortcut: 'Control + Shift + O',
        command: '播放到结尾',
        action: '从播放头播放到选择结尾',
      },
      {
        shortcut: 'Space',
        command: '播放/暂停',
        action: '开始或暂停播放',
      },
      {
        shortcut: 'Control + Space',
        command: '播放/暂停',
        action: '编辑文本栏时开始或暂停播放',
      },
      {
        shortcut: '=',
        command: '正时间码输入',
        action: '输入正时间码值将向前移动播放头、向前移动片段或修剪范围或片段，具体取决于选择',
      },
      {
        shortcut: 'Control + Command + Left',
        command: '上一个片段',
        action: '跳到上一项（在浏览器中）或上一个编辑点（在时间线中）',
      },
      {
        shortcut: 'Control + ;',
        command: '上一个标记',
        action: '将播放头移到上一个标记',
      },
      {
        shortcut: 'Shift + V',
        command: '设定监视角度',
        action: '将要浏览的角度设定为监视角度',
      },
      {
        shortcut: 'S',
        command: '浏览',
        action: '打开或关闭浏览',
      },
      {
        shortcut: 'Option + Shift + A',
        command: '开始/停止画外音录制',
        action: '开始或停止使用“录制画外音”窗口来录制音频',
      },
      {
        shortcut: 'K',
        command: '停止',
        action: '停止播放',
      },
      {
        shortcut: 'Control + K',
        command: '停止',
        action: '编辑文本栏时停止播放',
      },
      {
        shortcut: 'Command + [',
        command: '时间线历史记录后退',
        action: '在时间线历史记录中后退一个级别',
      },
      {
        shortcut: 'Command + ]',
        command: '时间线历史记录前进',
        action: '在时间线历史记录中前进一个级别',
      },
      {
        shortcut: 'Up',
        command: '向上',
        action: '跳到上一项（在浏览器中）或上一个编辑点（在时间线中）',
      },
      {
        shortcut: 'Control + Up',
        command: '向上',
        action: '编辑文本栏时，转至上一项（浏览器中）或上一个编辑点（时间线中）',
      },
    ],
  },
  {
    groupKey: '共享和工具',
    groupName: '共享和工具',
    shortcuts: [
      {
        shortcut: 'Command + E',
        command: '共享到默认目的位置',
        action: '使用默认目的位置共享选定的项目或片段',
      },
      {
        shortcut: 'A',
        command: '选择“箭头”工具',
        action: '将“选择”工具设为活跃',
      },
      {
        shortcut: 'B',
        command: '切割工具',
        action: '将“切割”工具设为活跃',
      },
      {
        shortcut: 'Shift + C',
        command: '裁剪工具',
        action: '激活裁剪工具并显示所选片段或播放头下方最顶部片段的屏幕控制',
      },
      {
        shortcut: 'Option + D',
        command: '变形工具',
        action: '激活变形工具并显示所选片段或播放头下方最顶部片段的屏幕控制',
      },
      {
        shortcut: 'H',
        command: '手工具',
        action: '将“手”工具设为活跃',
      },
      {
        shortcut: 'P',
        command: '位置工具',
        action: '将“位置”工具设为活跃',
      },
      {
        shortcut: 'Shift + T',
        command: '变换工具',
        action: '激活变换工具并显示所选片段或播放头下方最顶部片段的屏幕控制',
      },
      {
        shortcut: 'T',
        command: '修剪工具',
        action: '将“修剪”工具设为活跃',
      },
      {
        shortcut: 'Z',
        command: '缩放工具',
        action: '将“缩放”工具设为活跃',
      },
    ],
  },
  {
    groupKey: '显示',
    groupName: '显示',
    shortcuts: [
      {
        shortcut: 'Control + Option + 6',
        command: '片段外观：仅片段标签',
        action: '根据片段名称设置，显示仅带有片段名称、角色名称或活跃角度名称的时间线片段',
      },
      {
        shortcut: 'Control + Option + Down',
        command: '片段外观：缩小波形大小',
        action: '缩小时间线片段的音频波形大小',
      },
      {
        shortcut: 'Control + Option + 5',
        command: '片段外观：仅连续画面',
        action: '显示仅带有大型连续画面的时间线片段',
      },
      {
        shortcut: 'Control + Option + Up',
        command: '片段外观：增大波形大小',
        action: '增加时间线片段的音频波形大小',
      },
      {
        shortcut: 'Control + Option + 4',
        command: '片段外观：大型连续画面',
        action: '显示带有小型音频波形和大型连续画面的时间线片段',
      },
      {
        shortcut: 'Control + Option + 2',
        command: '片段外观：大型波形',
        action: '显示带有大型音频波形和小型连续画面的时间线片段',
      },
      {
        shortcut: 'Control + Option + 3',
        command: '片段外观：波形和连续画面',
        action: '显示带有等大的音频波形和视频连续画面的时间线片段',
      },
      {
        shortcut: 'Control + Option + 1',
        command: '片段外观：仅波形',
        action: '显示仅带有大型音频波形的时间线片段',
      },
      {
        shortcut: 'Shift + Command + -',
        command: '减少片段高度',
        action: '减少浏览器片段高度',
      },
      {
        shortcut: 'Shift + Command + =',
        command: '增加片段高度',
        action: '增加浏览器片段高度',
      },
      {
        shortcut: 'Shift + Command + ,',
        command: '显示较少的连续画面帧',
        action: '在浏览器片段中显示较少的连续画面帧',
      },
      {
        shortcut: 'Control + A',
        command: '显示/隐藏音频动画',
        action: '显示或隐藏所选片段或组件的音频动画编辑器',
      },
      {
        shortcut: 'Control + Y',
        command: '显示/隐藏浏览条信息',
        action: '在浏览器中浏览时显示或隐藏片段信息',
      },
      {
        shortcut: 'Control + V',
        command: '显示/隐藏视频动画',
        action: '显示或隐藏选定时间线片段的视频动画编辑器',
      },
      {
        shortcut: 'Shift + Command + .',
        command: '显示较多的连续画面帧',
        action: '在浏览器片段中显示较多的连续画面帧',
      },
      {
        shortcut: 'Option + Shift + Command + ,',
        command: '每个连续画面显示一帧',
        action: '每个连续画面显示一帧',
      },
      {
        shortcut: 'Option + Command + 2',
        command: '切换连续画面视图/列表视图',
        action: '在连续画面视图和列表视图之间切换浏览器',
      },
      {
        shortcut: 'Option + Shift + N',
        command: '查看片段名称',
        action: '在浏览器中显示或隐藏片段名称',
      },
      {
        shortcut: 'Command + +',
        command: '放大',
        action: '放大浏览器、检视器或时间线',
      },
      {
        shortcut: 'Command + –',
        command: '缩小',
        action: '缩小浏览器、检视器或时间线',
      },
      {
        shortcut: 'Shift + Z',
        command: '缩放至窗口大小',
        action: '缩放内容以适合浏览器、检视器或时间线的大小',
      },
      {
        shortcut: 'Control + Z',
        command: '缩放到样本',
        action: '打开或关闭放大音频样本',
      },
    ],
  },
  {
    groupKey: '窗口',
    groupName: '窗口',
    shortcuts: [
      {
        shortcut: 'Control + Option + Command + 3',
        command: '立体',
        action: '切换到 360° 检视器中的“立体”视图（仅立体）',
      },
      {
        shortcut: 'Control + Option + Command + 4',
        command: '立体单色',
        action: '切换到 360° 检视器中的“立体单色”视图（仅立体）',
      },
      {
        shortcut: 'Control + Option + Command + 5',
        command: '立体轮廓',
        action: '切换到 360° 检视器中的“立体轮廓”视图（仅立体）',
      },
      {
        shortcut: 'Command + 9',
        command: '后台任务',
        action: '显示或隐藏“后台任务”窗口',
      },
      {
        shortcut: 'Control + Option + Command + 6',
        command: '差分',
        action: '切换到 360° 检视器中的“差分”视图（仅立体）',
      },
      {
        shortcut: 'Command + 8',
        command: '前往“音频增强”',
        action: '将音频增强检查器设为活跃',
      },
      {
        shortcut: 'Command + 1',
        command: '转至浏览器',
        action: '激活浏览器',
      },
      {
        shortcut: 'Command + 6',
        command: '前往颜色板',
        action: '激活颜色板',
      },
      {
        shortcut: 'Option + Command + 4',
        command: '转至检查器',
        action: '激活当前检查器',
      },
      {
        shortcut: 'Command + 2',
        command: '转至时间线',
        action: '激活时间线',
      },
      {
        shortcut: 'Command + 3',
        command: '转至检视器',
        action: '激活检视器',
      },
      {
        shortcut: 'Control + Option + Command + 1',
        command: '左',
        action: '切换到 360° 检视器中的“左眼”视图（仅立体）',
      },
      {
        shortcut: 'Control + Tab',
        command: '下一个标签',
        action: '转至检查器或颜色板中的下一个面板',
      },
      {
        shortcut: 'Control + Shift + Tab',
        command: '上一个标签',
        action: '跳到检查器或颜色板中的上一个面板',
      },
      {
        shortcut: 'Option + Command + 8',
        command: '录制画外音',
        action: '显示或隐藏“录制画外音”窗口',
      },
      {
        shortcut: 'Control + Option + Command + 2',
        command: '右',
        action: '切换到 360° 检视器中的“右眼”视图（仅立体）',
      },
      {
        shortcut: 'Control + Command + V',
        command: '显示矢量显示器',
        action: '在检视器中显示矢量显示器',
      },
      {
        shortcut: 'Control + Command + W',
        command: '显示视频波形',
        action: '在检视器中显示波形监视器',
      },
      {
        shortcut: 'Shift + Command + 7',
        command: '显示/隐藏角度',
        action: '显示或隐藏角度检视器',
      },
      {
        shortcut: 'Shift + Command + 8',
        command: '显示/隐藏音频指示器',
        action: '显示或隐藏音频指示器',
      },
      {
        shortcut: 'Control + Command + 1',
        command: '显示/隐藏浏览器',
        action: '显示或隐藏浏览器',
      },
      {
        shortcut: 'Control + Command + 6',
        command: '显示/隐藏比较检视器',
        action: '显示或隐藏比较检视器',
      },
      {
        shortcut: 'Command + 5',
        command: '显示/隐藏效果浏览器',
        action: '显示或隐藏效果浏览器',
      },
      {
        shortcut: 'Control + Command + 5',
        command: '显示/隐藏转场浏览器',
        action: '显示或隐藏转场浏览器',
      },
      {
        shortcut: 'Control + Command + 3',
        command: '显示/隐藏事件检视器',
        action: '显示或隐藏事件检视器',
      },
      {
        shortcut: 'Command + 4',
        command: '显示/隐藏检查器',
        action: '显示或隐藏检查器',
      },
      {
        shortcut: 'Command + K',
        command: '显示/隐藏关键词编辑器',
        action: '显示或隐藏关键词编辑器',
      },
      {
        shortcut: 'Command + 1',
        command: '显示/隐藏资源库边栏',
        action: '显示或隐藏资源库边栏',
      },
      {
        shortcut: 'Shift + Command + 1',
        command: '显示/隐藏“照片和音频”边栏',
        action: '显示或隐藏“照片和音频”边栏',
      },
      {
        shortcut: 'Command + `',
        command: '显示/隐藏边栏',
        action: '显示或隐藏边栏',
      },
      {
        shortcut: 'Option + Command + 7',
        command: '显示/隐藏 360° 检视器',
        action: '显示或隐藏 360° 检视器',
      },
      {
        shortcut: 'Control + Command + 2',
        command: '显示/隐藏时间线',
        action: '显示或隐藏时间线',
      },
      {
        shortcut: 'Shift + Command + 2',
        command: '显示/隐藏时间线索引',
        action: '显示或隐藏打开项目的时间线索引',
      },
      {
        shortcut: 'Option + Command + 1',
        command: '显示/隐藏“字幕和发生器”边栏',
        action: '显示或隐藏“字幕和发生器”边栏',
      },
      {
        shortcut: 'Command + 7',
        command: '显示/隐藏视频观测仪',
        action: '在检视器中显示或隐藏视频观测仪',
      },
      {
        shortcut: 'Control + Option + Command + `',
        command: '叠加',
        action: '切换到 360° 检视器中的“叠加”视图（仅立体）',
      },
      {
        shortcut: 'Control + Command + 4',
        command: '切换检查器高度',
        action: '在检查器的半高视图和全高视图间切换',
      },
    ],
  },
]
