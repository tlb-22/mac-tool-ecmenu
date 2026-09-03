# Finder 菜单图标

通用证据范围见[平台边界](../Main.md)。本文件记录 Finder host 对菜单图像的布局观察，以及该行为对共享渲染算法形成的约束。

## AppKit 契约

`NSImage.alignmentRect` 是客户端可用于布局的对齐元数据；底边包含基线语义，其他边提供对应方向的对齐信息。图像绘制不会自动应用它，是否采用由客户端决定（macOS 26.5 SDK `NSImage.h:160–168`）。当前 `NSMenuItemCell` 已不再负责菜单绘制，因此不能据此推断 Finder host 会采用 `alignmentRect`。

## 项目观察

项目于 2026-08-21 在 macOS 26.6.1（25G76）、Xcode 26.6（17F113）和 macOS 26.5 SDK 中测得系统菜单字体为 13pt、cap height 约 9.16pt；相同字号和常规字重的 SF Symbol `.small` 比例生成约 9pt 高的主体 `alignmentRect`。`photo` 与 `photo.badge.arrow.down` 的主体区域相同，后者只增加主体外的 badge；完整尺寸会随渲染上下文产生约 1pt 的离散变化，不作为产品契约。

同次人工对比中，Finder 会把直接提交的非正方形图像拉伸进方形槽位，使 `eye` 横向压缩、`text.document` 横向拉宽。Finder 自带“快速查看”的 eye 约为 14×9pt，与上述系统度量相符。18pt 方形外壳实验还表明，Finder 根据完整图像外框适配槽位，不会因内部 `alignmentRect` 较小而保留主体尺度，因此 `alignmentRect` 不能作为不影响尺度的溢出预留区。

这些测量只描述当前验证环境，原始截图未作为仓库证据保留。

## 渲染约束

Finder 菜单图标先在调用端按系统字体和 Symbol 比例生成源图，再烘焙进方形画布。渲染器把源 `alignmentRect` 的中心平移到画布中心，不根据带 badge 的完整外框重新居中，也不进行第二次缩放；越界附属像素由画布裁切。输出不依赖 Finder 解释源图的 `alignmentRect`。

Launch Services 返回的应用图标没有 SF Symbols 的字形度量，因此保持宽高比、居中适配到相同画布且不放大。应用在菜单判定和图标读取之间消失时使用 SF Symbol 占位符；该真实竞态不改变已经冻结的菜单结构。

主应用与 Finder Extension 共用“按语义主体居中”和“不放大的等比画布适配”这两项无场景图像变换，各自仍拥有源图生成、画布和视觉参数。平台升级后应重新比较 Finder 自带菜单图标，并验证非方形 Symbol 的比例、badge 主体位置和附属图形裁切。
