# Project Index V1：项目级代码索引协议

> 状态：Draft 0.1.0。用于第一阶段 Java 分析器选型和输出验证；在真实 Maven 多模块项目验证通过前，不冻结为稳定协议。

## 1. 目标

Project Index 是 Code Map 对一个源码项目进行静态分析后产生的、与入口和 UI 无关的项目级索引。

它回答的是：

- 项目包含哪些模块、源码文件、类、接口和方法？
- 每个符号定义在哪里，完整源码范围是什么？
- 一次方法调用发生在哪里，编译期声明目标是什么？
- 一个虚调用有哪些在当前项目源码范围内发现的多态候选？
- 哪些调用或类型关系无法解析，原因是什么？

索引应当在整个项目范围建立一次，之后可按方法 ID 查询和遍历。入口可达子图由后续模块从 Project Index 中计算，不属于本协议的独立持久化事实。

## 2. 本阶段明确不做什么

Project Index 不包含：

- AI 生成的业务含义、方法输入输出说明和逻辑步骤；
- 逻辑步骤与调用点的归属关系；
- 画布坐标、线路通道、targetSide、lane 等布局信息；
- 当前页面的展开状态、缩放状态和跳转历史；
- 运行时调用轨迹或“某次执行一定进入哪个实现”的结论；
- 通用变量数据流、完整控制流图、所有标识符引用。

这些内容分别属于后续 AI 语义分析、地图组装、布局渲染或高级静态分析阶段。第一阶段只建立稳定的项目结构和调用事实。

## 3. 顶层结构

索引由以下部分组成：

| 字段 | 内容 | 说明 |
|---|---|---|
| project | 项目身份、源码快照、分析环境、分析器版本 | 用于判断索引是否过期 |
| modules | Maven/Gradle 等构建模块 | 多模块项目的边界 |
| files | 被纳入分析范围的源码文件 | 路径相对项目根目录 |
| symbols | 项目源码中定义的类型、方法、字段等符号 | 不把第三方依赖定义复制进来 |
| relations | 类型继承、接口实现、方法覆写 | 不承载调用发生位置 |
| callSites | 每一处源码调用表达式 | 调用图从这里派生 |
| diagnostics | 分析器警告、错误和未支持情况 | 不允许静默丢失分析失败 |

目录树不单独存储：由 file.path 的路径前缀生成。符号嵌套由 containerSymbolId 表示。这样不会同时维护两份容易不一致的目录/包含关系。

## 4. 身份、路径和源码位置

### 4.1 ID

- project.id：同一个本地项目的持久身份，不使用临时随机值反复变化。
- module.id：由模块相对路径及构建身份稳定生成。
- file.id：由规范化的项目相对路径稳定生成，例如 file:src/main/java/demo/OrderService.java。
- symbol.id：由语言、模块、限定名和签名构成稳定身份。方法签名必须区分重载；不能使用行号作为普通命名方法的唯一身份。
- callSite.id：由 caller、文件、调用位置和调用类型确定；它是源码快照内的调用点身份，源码编辑后允许变化。

匿名类、局部类、lambda 等没有稳定命名身份的结构，可以使用所属符号和源码位置生成合成 ID，并在文档/诊断中说明其稳定性边界。

ID 是不透明字符串。消费者不得通过拆分 ID 字符串来推导文件、类或方法信息，应读取显式字段。

### 4.2 路径

- 所有 path 均相对于项目根目录。
- 统一使用 POSIX 斜杠 /，Windows 路径也必须规范化。
- 不保存机器相关的绝对路径。
- 不允许路径逃逸项目根目录（例如 ../）。
- IDE 跳转时由运行环境将相对路径与当前项目根目录组合。

### 4.3 Range

所有 range 使用 LSP 兼容的位置约定：

- line 从 0 开始；
- character 从 0 开始，单位为 UTF-16 code unit；
- end 是排他边界；
- range.start 不得晚于 range.end；
- symbol.range 覆盖完整声明；symbol.selectionRange 覆盖可供导航选择的名称区域；
- 方法存在函数体时可提供 bodyRange；抽象方法或接口声明没有函数体时可省略或置 null。

UI 显示时再将 0-based 行号转换成用户熟悉的 1-based 行号。禁止在索引层混用两套坐标。

## 5. 符号与类型关系

symbols 只包含本次索引范围内的项目源码定义。第三方依赖的目标不作为 project symbol；调用点可以用 EXTERNAL_SYMBOL 描述其限定名和签名。

kind 是跨语言的通用类别，例如 class、interface、enum、record、function、method、constructor、field。语言专属的语法差异由 language analyzer 在归一化时处理，不把 Java AST 节点类型泄漏到通用协议。

containerSymbolId 表示词法包含关系，例如：

- OrderService 类包含 createOrder 方法；
- 外部类包含内部类；
- 类型包含字段或枚举常量。

relations 只表达需要显式查询的类型关系：

| kind | source → target | 含义 |
|---|---|---|
| EXTENDS | 子类/子接口 → 父类/父接口 | 继承 |
| IMPLEMENTS | 实现类 → 接口/trait | 实现 |
| OVERRIDES | 覆写方法 → 被覆写方法 | 方法覆写 |

不重复建立 CONTAINS relation；包含关系已经由 containerSymbolId 表达。

## 6. 调用点与多态候选

### 6.1 CallSite 是调用发生位置，不是调用边

每一次源码调用都单独记录一个 callSite。即使同一个方法在同一个方法体中被调用三次，也必须有三个不同的 callSite。

callSite 包含：

- callerSymbolId：最近的所属可调用符号；若调用出现在字段初始化等非方法上下文，可以为 null；
- enclosingSymbolId：最近的外围类型或符号，可用于保留非方法上下文；
- fileId、range、selectionRange：调用表达式及被调用名称的精确位置；
- callKind：普通调用、构造器调用、方法引用等；
- target：编译期声明目标；
- dispatchMode、dispatchCandidates、candidateCompleteness：虚调用及候选实现信息；
- lexicalContext：标明调用位于方法体、lambda、匿名类或初始化器等词法上下文。

调用图不是单独重复存储的一份数据。它由 callSites 派生：caller 指向 declared target，并额外连接 dispatchCandidates。

### 6.2 target 的四种状态

| target.kind | 含义 |
|---|---|
| PROJECT_SYMBOL | 声明目标是本项目索引中的符号 |
| EXTERNAL_SYMBOL | 声明目标属于第三方依赖或平台 API |
| UNRESOLVED | 分析器无法解析目标，必须保留表达式和原因 |
| DYNAMIC | 已知是动态调用，但静态分析无法给出确定声明目标 |

不得把“根据方法名猜测的目标”写成 PROJECT_SYMBOL。

### 6.3 多态处理规则

- declared target 表示编译期解析到的声明方法。
- dispatchCandidates 表示除 declared target 外，在当前项目源码范围内发现的可能覆写/实现方法。
- 每个候选都指向一个项目 symbol，并说明发现依据（IMPLEMENTS、OVERRIDES 等）。
- 不要求分析器判断运行时究竟选择哪个候选；地图后续将候选全部暴露，并标记为多态候选。
- candidateCompleteness = PROJECT_SCOPE_COMPLETE 只表示对当前纳入索引的项目源码范围完成了候选扫描，不代表覆盖运行时动态加载、外部插件或所有部署配置。
- 若 classpath、依赖源码或类型层次不完整，应标记 PARTIAL 或 UNKNOWN，不能伪装成完整结果。

DIRECT 调用的 candidateCompleteness 应为 NOT_APPLICABLE。VIRTUAL 调用即使当前没有发现额外候选，也不能因此声称运行时不存在外部覆写。

### 6.4 条件与执行时机

本协议记录静态源码事实，不把“条件调用”“必然调用”当作已确定的运行时结论。条件、循环、异常、lambda 延迟执行等控制流语义在后续 AI 逻辑步骤和结构化控制流增强中处理。lexicalContext 仅描述语法所在位置，不代表运行时一定执行。

## 7. 分析范围和完整性

第一版 Java adapter 的分析范围需要在运行报告中明确：

- 纳入了哪些模块和 source roots；
- 使用了哪个 JDK、构建工具、依赖 classpath；
- 哪些生成源码被纳入或排除；
- 哪些文件解析失败；
- 哪些符号绑定失败；
- 哪些调用目标为 external、unresolved 或 dynamic；
- 多态候选扫描是否完整。

索引器必须输出 diagnostics。无法解析的调用仍应保留为 UNRESOLVED/DYNAMIC callSite（若能识别调用表达式），不能直接丢弃。

第一版不承诺对反射、Spring 运行时代理、条件 Bean、消息总线和跨服务 RPC 还原完整运行时路径。它们应当被标注为静态分析边界，而不是让 AI 或程序猜测。

## 8. 与现有 map-data.js 的关系

当前模板的 map-data.js 是渲染数据，不是项目索引协议。两者不能合并。

| 现有 map-data.js | Project Index 来源/处理 |
|---|---|
| directories | 从 files.path 的目录前缀派生 |
| files | 从 files 映射 |
| methods | 从 method/function/constructor 等 callable symbols 映射 |
| method.source | 从 symbol.range 转换 |
| method.meaning、inputs、output、steps | 后续由 AI 语义分析生成，不属于 Project Index |
| calls | 从 callSites 的 declared target 和 dispatchCandidates 派生 |
| calls.sourceStepId | 后续根据 AI 步骤的源码证据范围与 callSite.range 关联 |
| targetSide、lane | 布局阶段计算，不属于索引事实 |
| label、certain/conditional 等展示文案/样式 | 后续由语义分析和渲染适配层生成 |

特别注意：callSite 不要求先有 LogicStep 才能存在。纯赋值、判断、循环等 AI 逻辑步骤也可以没有任何调用点。

## 9. 必须通过的完整性校验

JSON Schema 只负责字段形状。索引构建器还必须做跨对象一致性检查：

1. project/module/file/symbol/relation/callSite/diagnostic 各自 ID 唯一；
2. 文件路径和 file ID 唯一，所有路径均为项目相对路径；
3. file.moduleId、symbol.fileId、symbol.containerSymbolId 引用存在；
4. relation 两端 symbol 存在，且关系方向符合定义；
5. callSite.fileId 存在，caller/enclosing/target/candidate 引用存在；
6. PROJECT_SYMBOL target 和 dispatchCandidates 必须引用索引内 symbol；
7. dispatchCandidates 不得重复，也不得重复 declared target；
8. selectionRange 位于对应 range 内，所有 range 均在文件边界内；
9. callable symbol 的签名足以区分重载；
10. 未解析目标有明确 reason，并有对应诊断或可追踪状态；
11. 同一个调用表达式只生成一个 callSite；一个 callSite 的多态候选存放在同一记录中，不重复伪造源码调用点。

## 10. 第一阶段的冻结条件

本协议在以下工作完成前保持 Draft：

- 使用至少一个真实 Maven 多模块 Java 项目生成样本；
- 用重载、接口多实现、继承覆写、重复调用、递归、方法引用和 lambda 等案例验证；
- 对照 JDT 与 SCIP Java（必要时补充 AST 信息）的实际输出；
- 核对解析成功率、未解析原因、候选完整性和源码位置；
- 确认协议没有为了某个分析器而暴露其专有 AST 结构。

通过后再将 schemaVersion 从 0.1.0 升级为 1.0.0，并开始实现稳定的 Project Index 构建器。
