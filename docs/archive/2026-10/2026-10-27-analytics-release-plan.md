# 埋点增强提交、合并与发布记录

## 已确认授权

2026-10-27 用户明确要求 App 和网站两边的改动提交、合并 main 并发布。本次授权覆盖已完成埋点增强的 Git 提交/合并/推送、网站接收与查询/页面发布，以及 App 打包、上传、送审和审核后的发布。此前“不发布”的实施边界仅对应前一阶段，不阻止本次已授权操作。

## 执行边界

- 保留并提交原 main 上的使用分析文档，再合并已经通过独立复核的埋点变更；不覆盖未知用户修改。
- 不改业务架构、Watch 发送逻辑、业务 schema、账号与商店定价。
- 网站由网站仓库维护权威发布记录；先 Backend、Nginx 扩展接收，再 Analytics 与 ShotMarker 隐私页。生产配置在独立私有台账维护。
- App 使用既有签名和 Apple 账户；不导出或记录凭据，不自动接受新法律协议。需要账户交互时仅请用户完成登录验证。
- App Store 当前在本次现场核对为 1.3 Ready for Distribution，关联 Build 3；新版本及构建号在核对已有构建后设置，并保持 iPhone/Watch 版本一致。

## 步骤与验收

1. 检查两侧 main/远端、工作区及既有未提交内容；提交并合并推送。
2. 网站按其发布计划备份、部署和只读验收，不清空历史 Track，不写入虚构生产用户事件。
3. 核对 App Store/TestFlight 当前版本、签名、已有构建；设置新版本及构建号。
4. 在合并后的源码执行适当回归，创建 Release Archive，核对签名、嵌套 Watch、版本、隐私清单和 dSYM；导出/上传使用固定构建号。
5. 等待 Apple 处理，核对生成构建；更新与实际改动一致的发布和审核说明，选择构建并送审，按本次授权设置审核后发布。
6. 仅记录实际完成的状态。Apple 审核或登录/签名阻塞不视为已上架；更新 current 和带日期发布记录。

## 执行前核对

- 原 main 的使用分析文档已经单独提交；源实现与前轮通过验证的代码保持一致。
- App Store Connect 登录失效后用户已完成登录，现场页面显示 1.3 Ready for Distribution / Build 3。
- 签名预检发现历史 Xcode 账户配置条目、有效产品 profile，未见本地 Distribution identity；历史配置并不能证明账户会话或实际分发权限可用，后续实测见下文。
- TestFlight 现场核对最新版本为 1.3 / Build 3；本次补丁版本选择 1.3.1（4），四份 iPhone/Watch 产品配置保持一致，测试 target 的独立版本不变。
- 网站已部署并通过 HTTP 和静态资产核对；完整证据由网站仓库维护。App 构建/送审结果将在执行后记录，不预先宣称通过。

## 已执行验证

- App 功能提交 `a7da280`，原分析文档 `871d59b`；main 合并 `9953888`，版本准备提交 `f5c67ad`，均已推送。
- main `f5c67ad`、1.3.1（4）的 511 单元 + 1 诊断 UI 全部通过，0 失败/跳过。
- 同一源码的 Release Archive 成功；iPhone/Watch 均为 1.3.1（4），严格签名检查、隐私清单、最低系统及二进制/dSYM UUID 配对通过。原归档为 Development 签名，后续分发 IPA 重签名结果见下文。
- 首次 App Store 自动分发导出返回 `No Accounts` 和缺少 Distribution 私钥的错误；Xcode Accounts 现场为空，已请用户登录既有发布账户。未撤销或替换既有证书，未宣称 IPA 导出/上传成功。
- App Store Connect 中已建立 1.3.1 草稿，保存发布说明和审核说明，核对继承截图和隐私分类；选择审核通过自动发布，当时等待构建上传。

## 登录恢复后的签名限制（2026-10-27，已解决）

- 用户完成 Xcode 登录，GUI 确认账户已出现；复用同一 Archive 重试，没有重测、重打包或改业务代码。
- CLI 自动导出仍退出 70，错误变为 `No Account for Team` 及缺少该团队 Distribution 证书私钥；不能再归因于未登录。
- 改用同一 Archive 的 Organizer 自定义 App Store Connect 上传流程，明确关闭自动管理版本/构建号，保留符号上传，不限制为内部测试；随后选择自动签名。
- Organizer 实际返回 `Not a member of the team`，并表示没有能为该归档生成签名材料的团队 Admin 账户。GUI 账户具备商店后台管理角色，但签名资源不可用；未完成分发重签名或上传。
- [Apple 角色说明](https://developer.apple.com/help/account/access/roles)区分商店内容管理与开发者团队资源；[云签名说明](https://developer.apple.com/help/account/certificates/cloud-managed-certificates)描述 Organizer 支持的云签名路径。本次已实际尝试该路径，没有只凭 CLI 失败推断云签名不可用。
- 已打开 Xcode 添加账户窗口，请用户登录原团队持有人或已有签名权限的账户。没有退出已有账户、更改团队、扩大权限或撤销证书。当时等待账户权限恢复后复用当前 Archive 继续；最终处理结果见下文。

## 分发签名与上传（2026-10-27）

- 用户确认添加具备原团队签名权限的账户后，第三次自动导出成功；没有重跑测试或重新打包。
- 本地导出 IPA 的 iPhone/Watch 均通过严格 Distribution 签名与有效 App Store profile 检查，仍为 1.3.1（4）；两产品 dSYM UUID、最低系统、中文声明和主 App 隐私清单均核对通过。
- 本地核验 IPA 的 SHA-256 为 `25174a20d848bf664ddea9a44d85ed9fdee92f44a18e0de5de7470746fff1bac`。上传使用同一 Archive 再次自动打包，不将该散列声称为 Apple 收到包的逐字节证明。
- 唯一一次上传于 11:48:42 成功；构建号自动管理保持关闭，允许 App Store 分发并上传符号。TestFlight 现场显示 1.3.1（4）Processing。
- 稳定本地产物保留于原仓库忽略目录 `build/release-1.3.1-4/`；公开文档不保存原始日志、证书、账户、团队标识或凭据。

## Apple 处理及审核提交（2026-10-27）

- TestFlight 处理完成后，现场显示 Version 1.3.1 / Build 4 / Ready to Submit。
- 在商店 1.3.1 中选择并保存该构建，核对版本、发布说明和审核说明、继承截图、隐私问卷以及审核后自动发布设置。
- 点击 Add for Review 后进入 Ready for Review；继续点击 Submit for Review。11:54 返回 `1 Item Submitted`，审核详情显示 iOS App 1.3.1 / 1.3.1（4）/ `Waiting for Review`。
- 自动发布已设置为审核通过后发布，并立即向所有用户发布更新；没有更改价格、移除旧构建、清空用户数据或添加测试者。
- 本次签名、上传和审核提交步骤已经完成，网站已上线；Apple 审核通过及公开上架仍待外部结果，不能将 Waiting for Review 写成已上线。
- 发布包源码为 `f5c67ad`。之后的 main 提交只更新文档，已核对无业务/埋点/Watch 源码差异。近期已经实现的片段审核、取景/编号、任务编辑入口及维护修复均在其祖先提交中；首页改版和语音口令仍属于未实施方向。
- 本次没有执行真实 App Store/TestFlight 安装后的渠道及手机到生产端受控验收，也没有新增 Watch 真机验收。这些边界继续由 current 维护。
