# 选择集合与转换矩阵【暂不实现】

本页属于未来格式转换需求草案，不描述当前产品行为。

## 静态图片

PNG、JPG、HEIC、WebP、TIFF、BMP 之间可以互转，也都可以输出为 GIF 或 PDF。每个输入文件直接产生一个输出文件：

```text
photo.png → photo.jpg
photo.png → photo.gif   # 单帧
photo.png → photo.pdf   # 单页
```

目标格式与输入相同时，该输入跳过，不复制也不重新编码。批量选择含多种格式时，只要至少一个输入需要转换，目标项就可用：

```text
a.png + b.jpg 选择 PNG
→ a.png 跳过
→ b.png 新建
```

每个静态图片独立输出。多图转 PDF 不合并为多页文档，多图转 GIF 不合并为动画。

## GIF 输入

GIF 无论包含一帧还是多帧，都在源文件同级创建独立输出文件夹，并逐帧编号：

```text
loading.gif → PNG

loading/
├── loading-1.png
├── loading-2.png
└── loading-3.png
```

GIF 输入时不显示 GIF 目标项。多个 GIF 各自创建输出文件夹，互不共用。

## PDF 输入

PDF 无论包含一页还是多页，都在源文件同级创建独立输出文件夹，并逐页编号：

```text
document.pdf → PNG

document/
├── document-1.png
├── document-2.png
└── document-3.png
```

PDF 输入时不显示 PDF 目标项。多个 PDF 各自创建输出文件夹，互不共用。

## 输出容器语义

每个解码后的图像帧只生成一个目标文件：

- GIF 输出不包含动画、帧率、循环次数或帧延迟配置。
- PDF 输出不包含多页合并。
- GIF 的多帧与 PDF 的多页在输出端保持为多个独立文件。
