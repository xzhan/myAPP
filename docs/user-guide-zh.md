# PET Vocabulary Trainer 使用说明书

PET Vocabulary Trainer 是一个面向 PET 备考学生的 macOS 学习工具。它把词汇量测试、每日 45 词训练、阅读理解、错词复习和学习记录放在同一条学习主线上，帮助学生把“认识单词”推进到“会拼、会读、会在句子里理解”。

## 适合谁使用

- 正在准备 PET / Cambridge B1 Preliminary 的初中生。
- 需要把 PET 词汇按页、按单元持续复习的学生。
- 想把词汇学习和阅读理解衔接起来的家庭。
- 希望看到错词、复习提醒、学习历史和完成情况的家长。

## 安装和首次打开

1. 解压 `PETVocabularyTrainer-macOS.zip`。
2. 把 `PETVocabularyTrainer.app` 移动到 `Applications` 或任意常用文件夹。
3. 第一次打开时，如果 macOS 提示安全确认，请右键点击 app，选择 `Open`。
4. 如果使用发音检测，请在系统弹窗中允许麦克风和语音识别权限。

如果使用的是给新同学准备的 clean seed 版本，app 会在首次启动时自动安装内置的 Base / Quest / Reading 学习资源，但不会包含任何历史测试数据。

## 学习主线

首页按照学习流程组织：

1. Import：管理三类学习资源，通常只需要导入一次。
2. 45-Word Quest：每天学习或测试一个 PET page 的 45 个单词。
3. Reading Mission：完成同一 page 对应的阅读理解。
4. Reminder：复习之前没有掌握好的单词。
5. Trophies：查看历史练习、正确率、Page 进度和错词记忆曲线。

## 三类学习资源

### Base PDF

Base 是 PET 全量词库，主要用于建立稳定的词汇基础。它通常来自 `PET全.pdf`，按 66 页切分。Base 适合用来测试孩子整体词汇量和确定学习页面。

### Quest JSON

Quest 是每页 45 个词的强化训练数据，包含意思选择、拼写、句子翻译、例句和 Memory Tip。Quest 可以分批导入，已经导入的页面会显示为 Quest Enhanced。

### Reading

Reading 是和 Base / Quest 页码一一对应的阅读理解资源。完成某页 Quest 后，可以直接进入同页 Reading，形成“词汇到阅读”的闭环。

## 每日 45 词训练

进入 45-Word Quest 后，每个单词通常有三个核心维度：

1. Meaning：在句子语境中选择正确中文意思。
2. Spelling：根据中文提示和句子线索拼写英文单词。
3. Translation：理解中文句子并选择正确英文句子。

部分页面还会加入 Pronunciation Check。学生先听单词，再大声说出来。系统会给出温和反馈，例如 Almost heard 或 Heard clearly。发音表现不会强制阻断学习，但需要加强的单词会进入后续复习。

## 拼写规则

拼写检查会忽略大小写和重音差异。对于 PET 里常见的可选拼写，例如 `blond(e)`，系统会接受：

- `blond`
- `blonde`
- `Blond`
- `Blonde`
- `blond(e)`

这样可以避免学生因为英式/美式或括号可选字母被误判。

## Reading Mission

Reading 的推荐流程是：

1. 先看 5 个问题。
2. 带着问题阅读文章。
3. 读完后再开始逐题作答。
4. 如果答错，可以 retry 当前题目。

这个设计是为了培养考试中的阅读习惯：先读题，带着目标去文章中找信息。

## Review Rescue 和艾宾浩斯复习

当学生在意思、拼写、翻译或发音中出现薄弱项，单词会进入 Review Rescue。系统会按照类似艾宾浩斯记忆曲线的节奏提醒复习：

- 10 分钟
- 1 天
- 2 天
- 4 天
- 7 天

Review Rescue 每次会优先给出一个小复习包，避免一次面对太多错词。它的目标不是惩罚学生，而是在遗忘前把单词救回来。

## Trophies 学习记录

Trophies 是学习成果页，主要包含：

- 今日完成的练习数量。
- 平均正确率。
- 当前待复习单词数。
- 连续学习天数。
- Page 1-66 的 Quest / Reading 完成地图。
- 最新练习记录。
- 当前需要复习的错词和 Memory Tip。

家长可以通过 Trophies 快速判断：孩子今天有没有完成、哪几页完成了、哪些词还需要回来复习。

## 发音权限和常见问题

### 麦克风无法使用

如果学生第一次点击时拒绝了权限：

1. 打开 `System Settings`。
2. 进入 `Privacy & Security`。
3. 找到 `Microphone` 和 `Speech Recognition`。
4. 允许 `PETVocabularyTrainer`。
5. 回到 app 后点击检查或重新打开 app。

### 发音检测让孩子沮丧怎么办

发音部分采用 Gentle Pronunciation Coach。Almost heard 也会显示单词并给正向反馈，不会把孩子卡住。建议把它当作“开口练习提醒”，不是严格口语考试评分。

### 新同学打开后看到了旧数据

每台 Mac 的本地数据都保存在：

`~/Library/Application Support/PETVocabularyTrainer`

如果这台 Mac 以前运行过旧版本，新包不会自动覆盖旧数据。需要先删除或备份这个目录，再打开 clean seed 版本。

## 数据安全

学习数据默认保存在本机，不上传云端。包括：

- 导入的词库和阅读资源。
- 每个单词的掌握情况。
- Trophies 历史记录。
- Review Rescue 复习计划。

打包分享给别人时，clean seed 包只包含学习资源，不包含你的个人历史、进度、错词记录或 streak。

## 建议使用节奏

- 每天先看 Reminder，如果 due now 不多，可以先做 5 个 Review Rescue。
- 然后完成当天 Page 的 45-Word Quest。
- Quest 做完后继续完成同页 Reading。
- 最后看 Trophies，确认今日完成情况和待复习词。

一个稳定的日常节奏是：先救错词，再学新词，最后用阅读巩固。
