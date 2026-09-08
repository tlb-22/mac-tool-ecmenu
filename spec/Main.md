# ECMenu Spec

ECMenu 是一个提供高频文件操作的 macOS Finder 右键扩展。功能入口位于一级菜单，新建文件通过一层子菜单选择用户模板；正常执行保持静默，产品以原生、低配置和可预测为原则。

## 阅读路径

- [当前需求](Requirements/Main.md)：产品行为与验收边界。
- [技术知识](Technical/Main.md)：平台契约、项目实测、跨模块约束与设计动机。
- [未来提案](Proposals/Main.md)：已经形成稳定设计、但尚未进入当前产品范围的能力。

每个业务能力的高层执行流、模块协作、状态所有权和 API 边界由技术 spec 维护；局部算法和类型实现由源码与测试表达。[目录组织规则](Technical/Architecture/DirectoryRules.md)与[Technical spec 编写约束](Technical/Architecture/TechnicalSpecGuidelines.md)是新增和修改代码、文档的共同依据。尚未进入产品范围的稳定设计只进入未来提案。各目录通过链接关联，不重复维护同一结论。
