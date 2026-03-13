# Attention - 终极待办事项应用

## 愿景

Attention 是一款受 Things 3 启发的现代待办事项应用，追求极致的易用性、优雅的设计和强大的功能。支持 macOS、iOS、watchOS 三端，具备实时同步、Markdown 支持、AI 集成和丰富的交互动画。

---

## 一、核心数据模型

### 1.1 Todo（待办事项）
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 标题 |
| notes | String (Markdown) | 详细笔记，支持 Markdown |
| status | Enum | .inbox / .active / .completed / .cancelled |
| priority | Enum | .none / .low / .medium / .high |
| createdAt | Date | 创建时间 |
| modifiedAt | Date | 修改时间 |
| completedAt | Date? | 完成时间 |
| scheduledDate | Date? | 计划日期（"今天"/"某天"） |
| deadline | Date? | 截止日期 |
| tags | [Tag] | 标签 |
| project | Project? | 所属项目 |
| area | Area? | 所属领域 |
| checklist | [ChecklistItem] | 子任务清单 |
| recurrence | Recurrence? | 重复规则 |
| sortOrder | Int | 排序序号 |
| headingId | UUID? | 所属项目标题分组 |

### 1.2 Project（项目）
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 项目名称 |
| notes | String (Markdown) | 项目描述 |
| area | Area? | 所属领域 |
| status | Enum | .active / .completed / .cancelled |
| deadline | Date? | 截止日期 |
| headings | [Heading] | 项目内分组标题 |
| sortOrder | Int | 排序序号 |

### 1.3 Area（领域）
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 领域名称 |
| sortOrder | Int | 排序序号 |

### 1.4 Tag（标签）
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 标签名 |
| color | String | 标签颜色 |
| parentTag | Tag? | 父标签（支持嵌套） |
| sortOrder | Int | 排序序号 |

### 1.5 ChecklistItem（清单项）
| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 唯一标识 |
| title | String | 内容 |
| isCompleted | Bool | 是否完成 |
| sortOrder | Int | 排序序号 |

### 1.6 Recurrence（重复规则）
支持：每天、每周、每两周、每月、每年、自定义间隔

---

## 二、功能模块设计

### 2.1 核心视图（对标 Things 3）

| 视图 | 说明 |
|------|------|
| **收件箱 (Inbox)** | 快速捕获，零摩擦入口 |
| **今天 (Today)** | 今日待办 + 今日到期，支持"今晚"分组 |
| **计划 (Upcoming)** | 日历视图 + 计划安排的待办 |
| **随时 (Anytime)** | 无日期但 active 的待办 |
| **某天 (Someday)** | 暂时搁置的待办 |
| **日志 (Logbook)** | 已完成事项的归档 |
| **废纸篓 (Trash)** | 已删除事项，支持恢复 |

### 2.2 组织功能
- **项目 (Projects)**: 可包含待办和标题分组（Headings）
- **领域 (Areas)**: 生活领域分类（工作、个人、健康等）
- **标签 (Tags)**: 跨项目/领域的横向分类，支持嵌套
- **拖拽排序**: 所有列表支持拖拽重排

### 2.3 快捷操作
- **Quick Entry**: 全局快捷键唤出快速输入（macOS: ⌃Space）
- **Magic Plus**: Things 风格的 + 按钮，长按显示选项
- **批量操作**: 多选 + 批量移动/标记/删除
- **快捷键**: 完整的键盘快捷键支持（macOS）
- **Drag & Drop**: 在侧边栏和列表间拖拽

### 2.4 Markdown 笔记
- 实时 Markdown 预览/编辑切换
- 支持：标题、粗体、斜体、列表、代码块、链接、图片
- 语法高亮
- 行内代码和代码块

### 2.5 智能功能
- **自然语言日期解析**: "明天下午3点"、"下周一"
- **重复任务**: 灵活的重复规则
- **提醒通知**: 基于时间和地点的提醒
- **搜索**: 全文搜索（标题、笔记、标签）
- **筛选**: 按标签、日期、项目筛选

### 2.6 AI 集成（Claude MCP/Plugin）
- **智能分解**: 将大任务自动分解为子任务
- **智能建议**: 基于上下文建议截止日期、优先级
- **自然语言创建**: 对话式创建待办（"帮我安排下周的会议准备工作"）
- **日报/周报生成**: 自动生成完成事项摘要
- **MCP Server**: 作为 Claude MCP 工具暴露待办管理 API
- **Plugin 模式**: 支持第三方插件扩展

### 2.7 iOS 小组件 (Widgets)
| 小组件 | 尺寸 | 功能 |
|--------|------|------|
| **今日概览** | Small | 显示今日待办数量和进度环 |
| **今日列表** | Medium | 显示今日待办列表，可勾选完成 |
| **快速添加** | Small | 一键跳转到快速输入 |
| **即将到来** | Large | 显示未来几天的计划 |
| **项目进度** | Medium | 显示指定项目的进度 |
| **锁屏小组件** | Lock Screen | 今日待办数/下一个截止事项 |

### 2.8 watchOS 功能
- 查看今日待办
- 快速完成待办（勾选）
- 并发症（Complication）: 显示待办数量
- 语音快速添加
- 触觉反馈确认

### 2.9 多端同步
- **实时同步**: 基于 WebSocket 的实时推送
- **离线优先**: 本地 SwiftData 存储，网络恢复后自动同步
- **冲突解决**: CRDT 方案 + Last-Writer-Wins 兜底
- **增量同步**: 仅传输变更数据
- **端到端加密**: 用户数据在传输和存储时加密

---

## 三、技术架构

### 3.1 客户端技术栈
```
┌─────────────────────────────────────────┐
│           SwiftUI + SwiftData           │
│         (macOS / iOS / watchOS)          │
├─────────────────────────────────────────┤
│       Shared Swift Package (Core)       │
│  Models │ ViewModels │ Sync │ Services  │
├─────────────────────────────────────────┤
│  SwiftData  │  Network  │  Keychain    │
└─────────────────────────────────────────┘
```

- **UI**: SwiftUI（全平台共享 + 平台适配）
- **数据**: SwiftData（本地持久化）
- **架构**: MVVM + Repository Pattern
- **动画**: SwiftUI Animations + Custom Transitions
- **网络**: URLSession + WebSocket (Swift Concurrency)

### 3.2 同步服务端技术栈
```
┌──────────────────────────────────────┐
│          Nginx (Reverse Proxy)       │
├──────────────────────────────────────┤
│       Node.js + Fastify Server       │
├──────────────────────────────────────┤
│  PostgreSQL  │  Redis  │  WebSocket  │
└──────────────────────────────────────┘
```

- **框架**: Node.js + Fastify（高性能）
- **数据库**: PostgreSQL（持久化）
- **缓存**: Redis（会话 + 实时状态）
- **实时**: WebSocket（推送变更）
- **认证**: JWT + 设备令牌
- **部署**: Docker Compose

### 3.3 项目结构
```
attention/
├── AttentionApp/                    # Xcode 项目
│   ├── Shared/                      # 跨平台共享代码
│   │   ├── Models/                  # SwiftData 数据模型
│   │   ├── ViewModels/              # 视图模型
│   │   ├── Services/                # 业务逻辑服务
│   │   ├── Sync/                    # 同步引擎
│   │   ├── Network/                 # 网络层
│   │   └── Extensions/             # 工具扩展
│   ├── macOS/                       # macOS 专属
│   │   ├── Views/                   # macOS 视图
│   │   ├── QuickEntry/              # 全局快速输入窗口
│   │   └── MenuBar/                 # 菜单栏功能
│   ├── iOS/                         # iOS 专属
│   │   ├── Views/                   # iOS 视图
│   │   └── Widgets/                 # iOS 小组件
│   └── watchOS/                     # watchOS 专属
│       ├── Views/                   # watchOS 视图
│       └── Complications/          # 表盘并发症
├── AttentionServer/                 # 同步服务端
│   ├── src/
│   │   ├── routes/                  # API 路由
│   │   ├── services/                # 业务逻辑
│   │   ├── models/                  # 数据模型
│   │   ├── websocket/               # WebSocket 处理
│   │   └── middleware/              # 中间件
│   ├── migrations/                  # 数据库迁移
│   ├── Dockerfile
│   └── docker-compose.yml
├── AttentionMCP/                    # Claude MCP Server
│   └── src/
├── DESIGN.md                        # 本文档
├── DEVELOPMENT.md                   # 开发规划
└── CLAUDE.md                        # Claude Code 配置
```

---

## 四、UI/UX 设计原则

### 4.1 设计语言
- **极简**: 干净的界面，无多余元素
- **对比**: 亮色/暗色主题，精心调配的颜色层次
- **层次感**: 使用 Material blur、阴影营造空间感
- **品牌色**: 靛蓝/紫色渐变（体现 "Attention" 的专注感）

### 4.2 动画规范
- **列表项**: 完成时优雅的收缩消失 + 对勾动画
- **导航**: 平滑的转场动画
- **拖拽**: 实时的位置预览和弹性效果
- **Quick Entry**: 弹性滑入/淡出
- **进度环**: 流畅的填充动画
- **Spring 动画**: 主要使用 .spring() 系列

### 4.3 平台适配
- **macOS**: 三栏布局（侧边栏 + 列表 + 详情），键盘驱动
- **iOS**: 标签栏导航 + NavigationStack，手势驱动
- **watchOS**: 极简列表 + 数字表冠滚动

---

## 五、安全与隐私

- 本地数据使用 SwiftData 加密存储
- 网络传输全程 HTTPS/WSS
- 服务端数据加密存储
- 支持生物识别解锁（Face ID / Touch ID）
- 不收集用户使用数据
- 符合 GDPR 要求
