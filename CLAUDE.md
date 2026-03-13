# Attention - Claude Code 配置

## 项目概述
Attention 是一款类 Things 3 的终极待办事项应用，支持 macOS、iOS、watchOS。

## 技术栈
- 客户端: Swift 6.2+ / SwiftUI / SwiftData / MVVM
- 服务端: Node.js / Fastify / PostgreSQL / Redis / WebSocket
- MCP: Node.js MCP Server
- 同步服务器: ssh -i /Users/liam/Workspace/remote-claw/default.pem root@118.196.142.21 -p 22 -o ServerAliveInterval=30 -o ServerAliveCountMax=5

## 构建命令
- 构建全部: `xcodebuild -workspace AttentionApp/Attention.xcworkspace -scheme Attention build`
- 构建 macOS: `xcodebuild -workspace AttentionApp/Attention.xcworkspace -scheme "Attention (macOS)" build`
- 构建 iOS: `xcodebuild -workspace AttentionApp/Attention.xcworkspace -scheme "Attention (iOS)" build`
- 服务端: `cd AttentionServer && npm run dev`
- 服务端测试: `cd AttentionServer && npm test`

## 代码规范
- Swift strict concurrency mode
- MVVM + Repository Pattern
- 所有模型使用 SwiftData @Model
- 异步操作使用 async/await
- 提交信息: `type(scope): message`

## 关键文件
- DESIGN.md: 完整功能设计
- DEVELOPMENT.md: 开发阶段规划

## Git 远程仓库
- origin: git@github.com:SonicLiam/attention.git

## 品牌色
- Primary: Indigo (#6366F1)
- Accent: Pink (#EC4899)
