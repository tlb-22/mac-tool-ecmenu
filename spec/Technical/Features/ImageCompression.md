# 压缩图片技术决策

产品行为见[压缩图片需求](../../Requirements/Features/ImageCompression.md)。Finder 上下文见 [Finder 菜单语义](../Platform/Finder/ContextMenus.md)，输出后的批量选择见 [Finder 结果选择](../Platform/Finder/ResultSelection.md)。

## 类型能力与实际解码

`CGImageSourceCopyTypeIdentifiers()` 返回当前系统 ImageIO 声明支持的输入类型集合。该集合只能说明类型能力，不能证明某个具体文件内容有效；Finder Extension 只读取目录标志和内容类型来决定菜单是否出现，不在右键菜单构建期间解码图片。

PDF 即使可能被 ImageIO 识别，也被产品语义显式排除，因为命令处理图片而不是文档页。主应用执行时先尝试打开源文件，再创建 `CGImageSource`，从而区分访问权限失败和内容无法解码。Foundation 在读取已经消失的源文件时可返回 `CocoaError.fileReadNoSuchFile`，它与通用的 `fileNoSuchFile` 一起映射为目标失效。

## 参数窗口、进度与并发

参数使用标准非模态 `NSWindow`，通过 Swift 并发挂起当前请求等待确认，而不运行应用级模态循环。等待参数不会占住命令入口；其他命令可以继续执行，多个压缩请求也分别持有自己的目标快照和窗口。

单个批次按计划顺序逐项转换，并在每项结束后释放 ImageIO 临时对象，以限制多张大图的峰值内存并保持确定顺序。不同批次没有全局串行限制。

进度在用户确认参数后开始，参数窗口被取消或关闭时不产生进度任务。每个输入到达成功或失败终态时推进一次，因此计数表达已经处理的输入图片数，而不是成功输出数。通用进度窗口边界见[命令进度](../Runtime/CommandProgress.md)。

协作取消边界位于相邻输入之间，不主动中断正在进行的 ImageIO 编码或目标写入。取消意图等待当前输入到达终态，再阻止剩余输入开始；取消前的成功输出和问题仍按批量结果反馈。

## 主图像、方向与像素

多图像容器优先使用 `CGImageSourceGetPrimaryImageIndex` 返回的有效索引，否则使用索引 `0`；其余帧不进入输出。

EXIF orientation `5...8` 会交换视觉宽高，因此最大宽度约束应用于方向修正后的视觉宽度。`kCGImageSourceCreateThumbnailWithTransform` 负责应用方向，随后图像被绘制到精确尺寸的不透明 RGB 位图；画布先填充白色，使 Alpha 区域得到确定的 JPG 背景。

新的 `CGImageDestination` 只接收重新绘制的位图和 JPEG 质量，不复制源属性字典。因此源 EXIF、GPS、XMP 和容器附加帧不会写入结果。

项目在 macOS 26.6.1（25G76）使用 ImageIO 生成的样本验证了 JPEG 的 orientation `5...8` 像素方向、GIF 第一帧、HEIC 非首帧主图像，以及源相机、拍摄时间、GPS 和自定义 XMP 信息不进入输出。这些边界由 [ImageCompressionBoundaryTests](../../../Tests/ECMenuTests/ContextCommands/Features/ImageCompression/ImageCompressionBoundaryTests.swift) 覆盖；样本范围不代表所有系统支持的图片格式均已实测。

## 输出落盘与文件时间

每项先在内存中完成 JPEG 编码，再用 `.withoutOverwriting` 写入最终候选路径。编码失败不会创建目标，已有文件不会被替换。

目标目录写入失败时，受影响图片与失败目录是两个不同的事实：用户反馈以图片名称或数量说明其所在文件夹不可写，诊断同时保留源路径和目标目录。

创建时间和修改时间在 JPEG 成功落盘后设置。时间属性失败时保留已经生成的 JPG，并把该项作为问题反馈，不回滚文件。批量成功 URL 最终一次性交给 Finder 的批量选择 API。
