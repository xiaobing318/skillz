# 子代理目录维护规则

本目录保存 skillz 仓库的项目级 Codex 子代理 TOML 配置。根目录 `AGENTS.md` 仍是最高优先级项目指令；本文件只补充 `.codex/agents` 目录内子代理文件的维护细则，不能覆盖 `AGENTS.md`、`.codex/HelperScripts/README.md` 或用户本轮明确要求。

## 子代理清单

当前仓库维护七个核心项目子代理。它们分别对应 Codex 配置域审查、普通仓库改动一致性审查、仓库结构分析、脚本代码质量审查、脚本测试用例编写、脚本功能验证和会话状态维护，避免一个通用代理同时承担所有职责。

| 子代理 | 配置文件 | 主要用途 |
| --- | --- | --- |
| `codex_conformity_reviewer` | `CodexConformityReviewer.toml` | 审查 `AGENTS.md`、`.codex/**` 以及主代理明确标记为 Codex 相关的文件是否同步。 |
| `repo_conformity_reviewer` | `RepoConformityReviewer.toml` | 审查普通仓库文件改动后，文档、脚本、配置、schema、测试证据和资料入口之间的声明与事实是否对齐。 |
| `RepoStructureAnalysis` | `RepoStructureAnalysis.toml` | 分析仓库目录、平台入口、脚本职责和跨目录依赖，为主代理提供只读证据，不审查改动一致性。 |
| `repo_script_code_quality_reviewer` | `RepoScriptCodeQualityReviewer.toml` | 仓库脚本新增、删除或修改后的只读质量审查，重点检查参数、路径、副作用、安全边界、平台差异和说明同步。 |
| `repo_script_test_case_engineer` | `RepoScriptTestCaseEngineer.toml` | 在主代理指定范围内为仓库脚本变更补充自动化测试、测试数据或测试说明，不修改被测脚本主流程。 |
| `repo_script_functional_verifier` | `RepoScriptFunctionalVerifier.toml` | 在主代理指定范围内运行已静态确认的仓库脚本验证命令，记录结果、日志、副作用和清理情况。 |
| `session_state_maintainer` | `SessionStateMaintainer.toml` | 在会话生命周期内按主代理状态包维护 Codex Home 下的仓库外状态文件，辅助压缩恢复和防止失焦。 |

## 功能和使用场景

`codex_conformity_reviewer` 用于 Codex 配置域变更后的横向审查。修改 `AGENTS.md`、`.codex/config.toml`、`.codex/rules/**`、`.codex/agents/*.toml`、`.codex/agents/README.md` 或 `.codex/HelperScripts/**` 后，应使用它检查规则、清单、TOML 字段、说明文档、规则文件、平台发现入口、触发条件和证据要求是否同步。

`repo_conformity_reviewer` 用于普通仓库文件变更后的横向审查。修改根 `README.md`、`src/skillz/**`、`tests/**`、`SetupAndRun/**`、`Skills/**`、`.github/workflows/**` 下的说明文档、脚本、配置、schema、测试证据或 workflow 后，应使用它检查文档声明、脚本参数、平台范围、测试证据、编码规则和敏感示例信息是否互相对齐。

`RepoStructureAnalysis` 用于动手前或回答复杂问题前的只读结构分析。当任务需要理解目录分工、平台入口、脚本职责、配置和测试入口时，应先使用它定位真实文件、正确入口、关联资料和需要二次核验的风险点。它不读取 diff 来判断改动是否一致，也不输出“通过/失败”的一致性审查结论。

`repo_script_code_quality_reviewer` 用于仓库脚本新增、删除或修改后的深度只读审查。它从脚本真实参数、默认路径、写入/删除边界、日志输出、错误处理、平台分支、编码换行和文档声明出发，找出会误导执行或影响验收的风险。它只给问题清单和建议测试点，不写测试，也不执行动态验证。

`repo_script_test_case_engineer` 用于仓库脚本变更后的测试补充。主代理必须先给出明确写入范围，它才能新增或修改测试文件、测试数据或测试说明。它不修改被测脚本主流程，测试设计应覆盖参数契约、安全模式、主流程冒烟、失败路径、副作用与清理；脚本包含删除、覆盖或批量写入行为时，还要覆盖防越界场景。

`repo_script_functional_verifier` 用于仓库脚本变更后的功能正确性验证。主代理必须先静态确认脚本支持的参数和命令，再指定允许执行的命令、工作目录、写入范围和清理要求。该代理只能写日志、缓存和临时验证产物，验证后必须记录退出码、关键输出、副作用和清理结果；跨平台脚本必须在目标平台验证，不能用当前平台结果替代。

子代理 `session_state_maintainer` 用于会话生命周期状态维护。当前会话开始后，主代理必须优先尝试以 `fork_context=false` 的自包含任务包启动它，并在会话开始、关键节点、压缩前和恢复后持续发送状态包。主代理每次发送 `session_start`、`progress_checkpoint`、`pre_compaction`、`post_compaction_resume` 或 `final_summary` 状态包后，必须等待子代理返回成功写入结果。仅已发送请求、收到非成功结果、超时、字段缺失、路径未核验或只记录阻塞，都不算状态维护完成。主代理在主动压缩、准备请求压缩、长任务续跑前、多子代理等待前、上下文压力明显升高或预期可能自动压缩时，必须发送 `pre_compaction` 状态包并等待成功写入。自动压缩无法保证存在可执行的运行时前置 hook，因此不得把状态代理写成能自行感知压缩或自动轮询。

上下文恢复后的第一项主线前置动作必须是发送 `post_compaction_resume` 状态包并等待成功写入。失败、超时、字段缺失、路径不可写、路径未核验或返回非成功时，主代理必须修正任务包并重试，无法成功时必须停止主线并记录阻塞。第二项主线前置动作必须是读取并详细分析刚更新成功的 Codex Home `SessionState.md`，再结合压缩摘要、`AGENTS.md`、本文件、相关 TOML 和当前差别重建状态。读取失败、路径不一致或内容不是最新状态时，必须重试读取或重新触发状态维护。`SessionState.md` 是主代理压缩恢复时的状态外挂，必须在恢复后被主代理读取和分析，而不是只由子代理维护。它只维护 Codex Home 下的仓库外状态文件，默认路径协议为 `$CODEX_HOME/session-state/skillz/<MAIN_CODEX_THREAD_ID>/SessionState.md` 路径，不得写入当前仓库，不得执行主线任务，不得替代主代理判断。状态文件绝对路径和主会话 ID 必须由主代理在任务包中显式提供，不得让子代理根据它自己的 `CODEX_THREAD_ID` 推导。

用户明确要求使用子代理或并行子代理时，主代理应先判断任务能否按 Codex 配置域、普通资料域、平台目录、脚本职责或审查角色拆分。可并行拆分时，应并行派发必要子代理集合，等待全部结果后再汇总；当前环境无法实际调用对应子代理时，应读取对应 TOML 的 `developer_instructions` 完成等效只读审查。

`AGENTS.md` 的 5.3 代理编排流程图是项目级多子代理协作的编排审计基线。用户明确要求使用子代理或任务进入多子代理协作、脚本变更、Codex 配置域同步、普通资料一致性审查时，主代理必须逐项记录流程节点是否触发、选用子代理、并行或串行关系、任务包边界、等待条件、结论状态、裁剪理由、失败回退和验证边界。严格按照 5.3 执行不是机械派发所有子代理，而是保留适用节点并说明不适用节点。

`AGENTS.md` 中的 5.3 编排审计表字段模板是本目录子代理派发说明的同步来源。修改模板字段、裁剪口径、等待条件、失败回退或验证边界时，应同步核验本文件和 `CodexConformityReviewer.toml` 子代理。

## 派发和任务包规则

- 项目级子代理来自本目录 TOML。主代理使用这些子代理时，不使用完整历史 fork，不让子代理依赖未写入任务包的历史对话。
- 若当前工具同时支持 `agent_type` 和上下文 fork 选项，项目级 `agent_type` 子代理必须使用不 fork 完整历史的调用方式。
- 每次派发都必须提供自包含任务包，写清目标、背景摘要、范围、禁止事项、当前 OS、ISA、任务等级、允许读写范围、已核验证据、关键路径、期望输出和停止条件。
- 任务包必须说明 Python/uv/FastMCP 版本、工具链、构建方案、依赖根、构建目录、发布目录、发行版、网络、凭据或外部路径是否适用；适用时给出来源和核验结果，不适用时明确写“不适用”。
- 任务包必须列出子代理需要优先读取或核验的文件、diff、命令证据、日志证据或测试证据，并区分主代理已核验内容和子代理需要独立确认的内容。
- 派发 `session_state_maintainer` 时，任务包还必须包含由主代理解析的 Codex Home 状态文件绝对路径、路径来源、`CODEX_HOME` 核验证据、主会话 ID、主会话 ID 来源、状态文件保留和清理策略、状态包类型、当前状态包、禁止记录敏感信息要求，以及只允许写入该状态文件及其父目录的边界。不得只提供路径协议让子代理自行推导。
- 子代理收到任务包后，应先读取 `AGENTS.md`、`.editorconfig`、任务包指定文件和最小必要关联文件，确认任务等级、平台范围、读写边界、证据来源和输出格式。
- 子代理收到任务包后，应独立核验职责内关键细节。缺少关键背景或证据时，应报告缺失字段、影响原因和建议补充证据，不得用完整历史或猜测补齐。

## 压缩和恢复交接规则

- 发生主动压缩、自动压缩、上下文恢复或长任务续跑后，主代理继续工作前必须按 `AGENTS.md` 第 5 章重建状态摘要。
- 主代理发送任何状态包后，必须等待 `session_state_maintainer` 明确返回成功写入。失败、超时、字段缺失、路径未核验或返回非成功时，必须修正可修正问题后重试。无法成功写入时必须停止主线并记录阻塞，不得把“已发送请求”或“已记录阻塞”当作状态维护完成。
- 主代理在主动压缩、准备请求压缩、长任务续跑前、多子代理等待前、上下文压力明显升高或预期可能自动压缩时，必须发送 `pre_compaction` 状态包并等待成功写入。自动压缩无法保证主代理能在触发瞬间执行前置 hook，因此该检查点应在可预期风险出现时提前完成。
- 状态摘要至少包含 `.codex/agents/SessionStateMaintainer.toml` 中 `状态文件格式` 小节的全部章节；`AGENTS.md` 第 5 章负责规定主代理压缩恢复流程、成功门槛和必须覆盖的状态类别。
- 状态摘要格式必须与 `SessionStateMaintainer.toml` 的状态文件格式保持一致。恢复后缺失任一关键章节时，必须先补读 `AGENTS.md`、本文件、相关 TOML 和当前差别。
- 若这些状态章节在恢复后缺失，主代理必须重新读取 `AGENTS.md`、本文件、相关 `.codex/agents/*.toml` 和当前差别，不得用压缩前记忆补齐。
- 压缩恢复后的固定顺序是：第一动作发送 `post_compaction_resume` 状态包并等待状态文件成功写入。第二动作读取并详细分析刚更新成功的 Codex Home `SessionState.md`，再结合压缩摘要、`AGENTS.md`、本文件、相关 TOML 和当前差别重建状态。第一动作未成功、第二动作未完成前，不得继续主线编辑、测试、验证、最终答复或派发非恢复用途子代理。
- 压缩恢复后的状态维护握手必须写入 5.3 编排审计表和状态文件。若压缩摘要缺少 `session_state_maintainer` 的 agent id、状态文件路径或最近一次写入结果，主代理必须按缺失字段处理，重新核验 Codex Home 路径并发送 `post_compaction_resume` 状态包。该状态包必须显式包含主会话 ID、主会话状态文件绝对路径、路径来源、压缩摘要来源、压缩后重新核验的关键文件和当前差别。状态文件缺失、不可读、路径未核验、读取到的不是刚更新成功的状态、`post_compaction_resume` 写入失败或返回非成功时，必须重试可修正步骤。无法成功时必须记录阻塞或验证边界并停止主线，不得凭记忆补齐。
- 修改主动压缩交接字段、5.3 编排审计表或子代理派发规则后，应使用 `codex_conformity_reviewer` 子代理或等效只读审查确认 Codex 配置域仍一致。

## 功能边界

- `codex_conformity_reviewer` 只审查 Codex 配置域文件，不审查普通 skillz 文档、源码、脚本、schema、workflow 或测试证据。
- `repo_conformity_reviewer` 只审查普通仓库改动文件及直接关联文件之间的事实一致性，不审查 `AGENTS.md`、`.codex/**` 或其它 Codex 配置域文件，也不负责从零定位未知入口。
- `RepoStructureAnalysis` 只负责结构定位和证据梳理，不替代一致性审查，不读取 diff 判断改动是否已经满足验收。
- `repo_script_code_quality_reviewer` 默认只读，不负责修改文件、生成补丁、编写测试或运行验证命令。
- `repo_script_test_case_engineer` 只能在主代理指定的测试文件、测试数据或测试说明范围内写入，不得修改被测脚本主流程，不得扩大写入范围。
- `repo_script_functional_verifier` 只能写入主代理指定的日志、缓存和临时验证产物，不得修改源码、测试、文档、schema 或 Codex 配置。
- `session_state_maintainer` 只能写入主代理指定的 Codex Home 状态文件及其父目录，不得修改仓库文件、Codex 配置、普通文档、脚本、测试或 schema 校验文件。
- 子代理输出只能作为证据来源和建议。任务等级判定、修改取舍、验证结论和面向用户的最终答复仍由主代理负责。

## 文件范围

- `*.toml` 是 Codex 子代理配置文件，文件内字段决定子代理名称、描述、权限和开发者指令。
- `README.md` 是目录级说明文档，不是子代理配置文件，不应被当作 agent 加载。
- `.codex/HelperScripts/**` 是 Codex 上下文发现脚本和说明文件。当前只用于发现平台信息，不负责构建、测试、安装、打包、发布或下载依赖。
- `session_state_maintainer` 维护的 `SessionState.md` 应位于 Codex Home 下的 `session-state/skillz/<MAIN_CODEX_THREAD_ID>/`，不是仓库内容，不应放入 `.codex/agents/` 或普通 skillz 项目资料目录或 Skills 内容。它是主代理压缩恢复时的状态外挂，恢复后必须由主代理读取并详细分析。
- 不在本目录保存机器专属 profile、依赖快照、构建目录、发布目录、凭据、代理地址或其它只适用于单台机器的长期配置。

## TOML 字段规则

- 子代理 TOML 应使用 Codex 官方字段，例如 `name`、`description`、`sandbox_mode`、`developer_instructions`、`nickname_candidates`。
- 不得使用非官方 `nickname` 字段。
- 通常不在子代理 TOML 中固定 `model`、`service_tier` 或 `model_reasoning_effort`，子代理继承主会话和项目配置。除非后续任务明确要求按角色分级，并同步更新相关说明。
- 只读审查或分析代理必须显式设置 `sandbox_mode = "read-only"`。
- 需要写测试或写临时验证产物的脚本代理可使用 `sandbox_mode = "workspace-write"`，但必须在 `developer_instructions` 中写明允许写入范围和禁止修改对象。
- 不把 Python 版本、uv/uvx 版本、FastMCP 版本、skills root、transport、host/port/path、CORS、Docker 配置、客户端环境、机器绝对路径、依赖快照、构建目录或发布目录写成通用规则。这些上下文只能来自主代理当轮任务包中的已核验证据。

## 命名规则

- 文件名优先使用能说明职责的 PascalCase，例如 `CodexConformityReviewer.toml` 和 `RepoConformityReviewer.toml`。
- `name` 字段使用稳定的 snake_case，例如 `codex_conformity_reviewer`。
- `RepoStructureAnalysis` 是当前仓库已有的历史兼容名称，暂时保留 PascalCase 的 `name` 字段；若后续改成 snake_case，必须同步更新文件名、`name` 字段、`AGENTS.md` 和本文件。
- 文件名、`name`、`description` 和 `AGENTS.md` / 本文件中的清单必须能互相对应，避免旧名称残留成误导入口。

## 同步要求

- 更新子代理清单、名称、权限、职责、派发时机、禁止事项或输出要求时，必须同步核验 `.codex/agents/*.toml`、本文件和 `AGENTS.md`。
- 新增、删除、重命名子代理 TOML 或调整子代理职责时，必须同步更新本文件的子代理清单，并检查 `AGENTS.md` 第 5 章的子代理清单、代理编排流程图、流程编号对应表、派发时机和任务包要求是否仍一致。
- 修改 `session_state_maintainer`、状态文件路径协议、状态 Markdown 格式、常驻轮询口径或压缩恢复交接字段时，必须同步核验 `AGENTS.md`、本文件、`CodexConformityReviewer.toml` 和 `SessionStateMaintainer.toml` 子代理。
- 新增、删除或修改 `.codex/HelperScripts/**` 时，必须同步核验 `AGENTS.md`、`.codex/HelperScripts/README.md` 和 `CodexConformityReviewer.toml` 中的平台发现说明是否一致。
- 修改本目录规则后，应使用 `codex_conformity_reviewer` 或等效只读审查核对 Codex 配置域是否发生漂移。
- 当前会话无法热加载新增或重命名后的子代理时，主代理应读取对应 TOML 的 `developer_instructions`，按同样口径完成等效只读审查，并把该限制写入最终验证边界。
- 修改项目级子代理派发、完整历史 fork、任务包字段、自查或回补规则时，必须同步核验 `AGENTS.md`、本文件和全部 `.codex/agents/*.toml` 的要求是否一致。
- 修改 5.3 编排审计表、压缩/压缩恢复交接规则或子代理派发基线时，必须同步核验 `AGENTS.md`、本文件和 `CodexConformityReviewer.toml` 文件。
