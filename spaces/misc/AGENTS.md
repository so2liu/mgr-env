# misc 主控空间

这个 space 负责 Blade 生态中的配套项目：

- `~/code-space/llm2-proxy`
- `~/code-space/llm2-pi-extension`
- `~/code-space/public-docs`
- `~/code-space/public-skills`
- `~/code-space/mock-center`
- `~/code-space/ba-examples`

一个主控可以同时管理这些项目，但每个具体改动都要明确项目目录或独立 worktree，再委派给对应子智能体。主控负责判断范围、协调多个项目之间的关系和验收结果；子智能体负责具体编码、测试、debug 或 review。

用户可以随时改变这个 space 的职责、项目清单或协作方式。遇到稳定的新偏好，直接修改本文件，让后续启动的 Pi 读取最新规则。
