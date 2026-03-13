# Attention - 开发规划

## 开发阶段

### Phase 1: 基础架构 (Foundation)
**分支**: `phase/1-foundation`
**目标**: 搭建项目骨架，实现核心数据层

- [ ] 创建 Xcode 多平台项目（macOS + iOS + watchOS）
- [ ] 定义 SwiftData 模型（Todo, Project, Area, Tag, ChecklistItem）
- [ ] 实现 Repository 层（CRUD 操作）
- [ ] 搭建 MVVM 架构（基础 ViewModel）
- [ ] 创建 App 入口和基础导航结构
- [ ] 配置 App Group 用于 Widget 数据共享
- [ ] 建立 .gitignore 和项目配置

### Phase 2: 核心 UI - macOS (Core UI - macOS)
**分支**: `phase/2-core-ui-macos`
**目标**: 实现 macOS 主界面

- [ ] 三栏布局（Sidebar + List + Detail）
- [ ] 侧边栏：收件箱/今天/计划/随时/某天/日志
- [ ] 侧边栏：项目列表和领域分组
- [ ] 待办列表视图（TodoListView）
- [ ] 待办详情视图（TodoDetailView）
- [ ] 创建待办（内联创建 + 快捷键）
- [ ] 完成/取消待办动画
- [ ] 标签管理界面
- [ ] 项目视图（含 Headings）
- [ ] 暗色/亮色主题

### Phase 3: 核心 UI - iOS (Core UI - iOS)
**分支**: `phase/3-core-ui-ios`
**目标**: 实现 iOS 主界面

- [ ] TabBar 导航结构
- [ ] 各视图的 iOS 适配
- [ ] 手势操作（滑动完成/删除/计划）
- [ ] Sheet 式详情编辑
- [ ] Magic Plus 浮动按钮
- [ ] 下拉搜索
- [ ] Haptic 反馈

### Phase 4: 高级交互 (Advanced Interactions)
**分支**: `phase/4-advanced`
**目标**: 完善交互体验

- [x] Markdown 编辑器（笔记区域）
- [x] 全局 Quick Entry（macOS）
- [x] 拖拽排序（列表内 + 跨列表）
- [x] 批量选择和操作
- [x] 自然语言日期解析
- [x] 重复任务
- [x] 键盘快捷键（macOS 全套）
- [x] 搜索和筛选
- [x] 提醒通知（UserNotifications）
- [ ] 精细动画打磨

### Phase 5: 同步服务 (Sync Server)
**分支**: `phase/5-sync-server`
**目标**: 搭建同步后端，实现多端同步

- [ ] 服务器环境搭建（Docker + PostgreSQL + Redis + Nginx）
- [ ] Fastify API 服务
- [ ] 用户注册/登录（JWT）
- [ ] RESTful CRUD API
- [ ] WebSocket 实时推送
- [ ] 同步协议设计（增量同步 + 冲突解决）
- [ ] 客户端同步引擎
- [ ] 离线队列 + 自动重连
- [ ] 端到端加密

### Phase 6: watchOS + Widgets (Extensions)
**分支**: `phase/6-extensions`
**目标**: watchOS 应用和 iOS 小组件

- [ ] watchOS 今日待办列表
- [ ] watchOS 快速完成
- [ ] watchOS 语音添加
- [ ] watchOS Complication
- [ ] iOS Widget: 今日概览 (Small)
- [ ] iOS Widget: 今日列表 (Medium)
- [ ] iOS Widget: 快速添加 (Small)
- [ ] iOS Widget: 即将到来 (Large)
- [ ] iOS Widget: 锁屏小组件
- [ ] Widget 交互（iOS 17+ Interactive Widgets）

### Phase 7: AI 集成 (AI Integration)
**分支**: `phase/7-ai`
**目标**: Claude MCP Server 和 AI 功能

- [ ] Attention MCP Server（Node.js）
- [ ] MCP Tools: 创建/查询/更新/完成待办
- [ ] MCP Tools: 项目管理
- [ ] 应用内 AI 助手界面
- [ ] 智能任务分解
- [ ] 日报/周报生成
- [ ] 自然语言任务创建

### Phase 8: 打磨发布 (Polish & Release)
**分支**: `phase/8-polish`
**目标**: 最终打磨和发布准备

- [ ] 性能优化（大量数据场景）
- [ ] 无障碍访问（VoiceOver）
- [ ] 本地化（中/英）
- [ ] 应用图标和启动画面
- [ ] App Store 元数据
- [ ] 数据导入/导出
- [ ] 使用引导（Onboarding）
- [ ] 全面测试

---

## 技术约定

### 代码规范
- Swift 6.2+ strict concurrency
- SwiftUI 声明式优先
- 使用 Swift Concurrency（async/await）
- 模型命名：PascalCase
- 变量/函数命名：camelCase
- 文件组织按功能模块

### Git 约定
- 主分支: `main`
- 功能分支: `phase/N-name`
- 提交信息格式: `type(scope): message`
  - feat: 新功能
  - fix: 修复
  - refactor: 重构
  - style: UI 样式
  - docs: 文档
  - chore: 构建/配置

### 品牌色彩
- Primary: #6366F1 (Indigo 500)
- Secondary: #8B5CF6 (Violet 500)
- Accent: #EC4899 (Pink 500)
- Success: #10B981 (Emerald 500)
- Warning: #F59E0B (Amber 500)
- Danger: #EF4444 (Red 500)
