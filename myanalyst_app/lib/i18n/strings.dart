// All user-facing UI text, in English and Simplified Chinese.
//
// One class, two languages, no code generation: `S.of(context).x` returns
// the string for the current language. Text written by the AI (summaries,
// answers) comes from the server already in the chosen language.

import 'package:flutter/widgets.dart';

import '../data/repository.dart';
import '../state/app_controller.dart';

enum AppLanguage { en, zh }

class S {
  const S(this.lang);
  final AppLanguage lang;

  static S of(BuildContext context) => S(AppScope.of(context).language);

  bool get zh => lang == AppLanguage.zh;
  String _(String en, String zh) => this.zh ? zh : en;

  String get code => zh ? 'zh' : 'en';
  String get switchLanguage => _('中文', 'English');
  String get demoData => _('Demo data', '演示数据');
  String get demoNotConnected => _('Demo data, not connected to a server', '演示数据，未连接服务器');

  // ---- auth ---------------------------------------------------------------
  String get signIn => _('Sign in', '登录');
  String get createAccount => _('Create account', '注册账号');
  String get signOut => _('Sign out', '退出登录');
  String get username => _('Username', '用户名');
  String get password => _('Password', '密码');
  String get authTitle => _('Your finances, explained.', '看懂你的经营数据。');
  String get authLead => _(
      'MyAnalyst reads your sales and bank records, shows how long your cash will last, and explains '
          'your options in plain language.',
      'MyAnalyst 读取你的销售和银行流水，告诉你现金还能撑多久，并用通俗的语言解释你有哪些选择。');
  String get haveAccount => _('Already have an account? Sign in', '已有账号？去登录');
  String get noAccount => _('New here? Create an account', '第一次使用？注册账号');
  String get usernameRule => _('3 to 64 letters, numbers or . _ - @', '3–64位字母、数字或 . _ - @');
  String get passwordRule => _('At least 8 characters', '至少8个字符');
  String get usernameInvalid => _('Use 3 to 64 letters, numbers or . _ - @', '请使用3–64位字母、数字或 . _ - @');
  String get passwordTooShort => _('Use at least 8 characters.', '密码至少需要8个字符。');
  String get demoSignInNote =>
      _('Demo mode: any username and password will work.', '演示模式：任意用户名和密码均可登录。');
  String get securityNote => _(
      'Passwords are stored as salted scrypt hashes. Your session is kept in the phone\'s secure storage.',
      '密码以加盐 scrypt 哈希保存。登录状态保存在手机的安全存储中。');

  // ---- biometric lock -------------------------------------------------------
  String get lockedTitle => _('MyAnalyst is locked', 'MyAnalyst 已锁定');
  String welcomeBack(String user) => _('Welcome back, $user.', '欢迎回来，$user。');
  String get lockedBody => _('Your financial data stays hidden until you confirm it\'s you.', '确认身份之前，你的财务数据不会显示。');
  String get unlockWithFingerprint => _('Unlock with fingerprint', '使用指纹解锁');
  String get usePasswordInstead => _('Sign in with password instead', '改用密码登录');
  String get lockBrokenBody => _(
      'The fingerprints on this phone have changed, so the saved sign-in was cleared for your security. '
          'Please sign in with your password.',
      '这部手机的指纹已更改，为了安全，已清除保存的登录状态。请使用密码登录。');
  String get offerTitle => _('Unlock with your fingerprint next time?', '下次使用指纹解锁？');
  String get offerBody => _(
      'Your sign-in will be locked with a key only your fingerprint can open, and the app locks itself after '
          '5 minutes in the background.',
      '你的登录状态将由只有指纹才能打开的密钥保护，应用在后台超过5分钟会自动锁定。');
  String get turnOn => _('Turn on', '开启');
  String get notNow => _('Not now', '暂不');
  String get fingerprintUnlock => _('Fingerprint unlock', '指纹解锁');
  String get on => _('On', '开');
  String get off => _('Off', '关');
  String get biometricFailed => _('Fingerprint unlock couldn\'t be changed. Please try again.', '无法更改指纹解锁设置，请重试。');

  // ---- start --------------------------------------------------------------
  String get startTitle => _('Start with a spreadsheet.', '从一份表格开始。');
  String get startLead => _(
      'Upload a CSV of your sales or bank transactions. MyAnalyst tidies it, works out your cash flow, '
          'charts what matters and writes up what it finds. Then you can ask it questions in plain language.',
      '上传销售记录或银行流水的 CSV 文件。MyAnalyst 会整理数据、计算现金流、绘制关键图表并写出分析结论。'
          '之后你可以直接用中文提问。');
  String get chooseCsv => _('Choose a CSV file', '选择 CSV 文件');
  String csvHint(int mb) => _('CSV only, up to $mb MB. First row should be column names.', '仅支持 CSV，最大 $mb MB。第一行应为列名。');
  String get noFile => _('NO FILE TO HAND?', '手边没有文件？');
  String get openSample => _('Open one of these samples to see what you get.', '打开一个示例，看看效果。');
  String rowsCount(int n, String formatted) => _('$formatted rows', '$formatted 行');
  String filesCount(int n) => _(n == 1 ? '1 file' : '$n files', '$n 个文件');
  String get yourAnalyses => _('YOUR ANALYSES', '我的分析');
  String get noAnalysesYet => _('Analyses you run are saved here.', '你做过的分析会保存在这里。');
  String get delete => _('Delete', '删除');
  String get deleteTitle => _('Delete this analysis?', '删除这份分析？');
  String get deleteBody => _('The uploaded file, answers and rules are removed from the server. This can\'t be undone.',
      '服务器上的文件、问答和规则都会被删除，且无法恢复。');
  String get cancel => _('Cancel', '取消');
  String runwayShort(String months) => _('$months mo runway', '可撑 $months 个月');
  String gapShort(String date) => _('Cash gap ~$date', '约 $date 现金缺口');
  String get whatNext => _('WHAT HAPPENS NEXT', '接下来会发生什么');
  List<(String, String)> get howItWorks => zh
      ? const [
          ('整理', '修正日期、货币符号和缺失值，标记异常值但不改动，每一步都有记录。'),
          ('现金流', '计算每月收支、现金能撑多久，并提前预警可能出现的资金缺口。'),
          ('解读', '用通俗的语言写出数据说明了什么，并解释可选的融资方式。'),
          ('提问', '自动编写并运行分析来回答你的问题，过程完全可查。'),
        ]
      : const [
          ('Tidy', 'Fixes dates, currency symbols and gaps, flags unusual values without changing them, and logs every step.'),
          ('Cash flow', 'Works out money in and out each month, how long your cash lasts, and warns you before it runs short.'),
          ('Explain', 'Writes a plain-language read of the numbers and explains the financing options that fit.'),
          ('Ask', 'Answers your questions by writing and running the analysis, and shows its working.'),
        ];
  String get privacyPromise => _(
      'Your file is analysed on the MyAnalyst server. Names, phone numbers, emails and ID numbers are hidden '
          'before anything is sent to the AI, and code runs in a sealed sandbox with no internet access.',
      '文件在 MyAnalyst 服务器上分析。姓名、电话、邮箱和证件号码在发送给 AI 之前都会被隐藏，'
          '分析代码在无法联网的隔离沙箱中运行。');

  List<(String, String)> get processingSteps => zh
      ? const [
          ('读取文件', '检查行和列'),
          ('整理数据', '日期、货币符号、缺失值和异常值'),
          ('计算现金流', '每月收支、现金可维持时间和缺口预警'),
          ('保护隐私', '在发送给 AI 前隐藏个人信息'),
          ('解读各列含义', '每个字段最可能代表什么'),
          ('撰写摘要', '用通俗语言总结结果'),
        ]
      : const [
          ('Reading the file', 'Checking rows and columns'),
          ('Tidying the data', 'Dates, currency symbols, gaps and unusual values'),
          ('Working out cash flow', 'Monthly in and out, runway and gap warning'),
          ('Protecting privacy', 'Hiding personal details before the AI sees anything'),
          ('Describing each column', 'What each field most likely means'),
          ('Writing the summary', 'A plain-language read of the results'),
        ];
  String get usuallyUnderMinute => _('This usually takes under a minute.', '通常不到一分钟。');
  String get tryAgain => _('Try again', '重试');
  String get chooseAnother => _('Choose another file', '选择其他文件');

  // ---- validation / errors -----------------------------------------------
  String get errNotCsv => _('MyAnalyst reads CSV files. In Excel or WPS, use File › Save as › CSV.',
      'MyAnalyst 只读取 CSV 文件。可在 Excel 或 WPS 中选择 文件 › 另存为 › CSV。');
  String get errEmpty => _('That file is empty.', '这个文件是空的。');
  String errTooBig(int mb) => _('That file is larger than $mb MB. Try exporting a shorter date range.',
      '文件超过 $mb MB。请尝试导出较短的时间段。');
  String get errBinary => _('That file doesn\'t look like text. Check it\'s a CSV and not a renamed spreadsheet.',
      '这个文件看起来不是文本，请确认它是 CSV 而不是改了扩展名的表格文件。');
  String get errUnreadable => _('The file couldn\'t be read. Try choosing it again.', '无法读取文件，请重新选择。');
  String get errGeneric => _('Something went wrong. Please try again.', '出了点问题，请重试。');

  String failure(Failure f) => switch (f) {
        Failure.network => _('Can\'t reach the MyAnalyst server. Check your connection and try again.', '无法连接 MyAnalyst 服务器，请检查网络后重试。'),
        Failure.timeout => _('This is taking longer than expected. Please try again in a moment.', '耗时比预期长，请稍后重试。'),
        Failure.rejected => _('The server couldn\'t accept that. Check the file or text and try again.', '服务器无法接受该请求，请检查文件或内容后重试。'),
        Failure.signedOut => _('Your session has ended. Please sign in again.', '登录已过期，请重新登录。'),
        Failure.wrongCredentials => _('Wrong username or password.', '用户名或密码错误。'),
        Failure.usernameTaken => _('That username is taken.', '该用户名已被使用。'),
        Failure.notFound => _('This analysis is no longer available.', '这份分析已不存在。'),
        Failure.tooLarge => _('That file is too large to upload.', '文件太大，无法上传。'),
        Failure.rateLimited => _('Too many attempts. Wait a few minutes and try again.', '尝试次数过多，请几分钟后再试。'),
        Failure.server => _('Something went wrong on the server. Please try again.', '服务器出现问题，请重试。'),
        Failure.unreadable => _('The server sent a response the app couldn\'t read.', '无法读取服务器返回的内容。'),
      };

  // ---- navigation ---------------------------------------------------------
  String get navOverview => _('Overview', '概览');
  String get navCash => _('Cash flow', '现金流');
  String get navData => _('Data', '数据');
  String get navAsk => _('Ask', '提问');
  String get navRules => _('Rules', '规则');
  String get dataset => _('DATASET', '数据集');
  String rowsCols(String rows, int cols) => _('$rows rows · $cols columns', '$rows 行 · $cols 列');
  String opened(String t) => _('Opened $t', '打开于 $t');
  String get newAnalysis => _('New analysis', '新的分析');
  String get backToStart => _('Back to start', '返回首页');
  String get leaveTitle => _('Leave this analysis?', '离开这份分析？');
  String get leaveBody => _('It stays saved under Your analyses. Questions asked in this session will be cleared from the screen.',
      '分析会保存在"我的分析"中，本次提问记录将从屏幕上清除。');
  String get leave => _('Leave', '离开');
  String get exportPdf => _('Export report (PDF)', '导出报告（PDF）');
  String get exportShort => _('Report', '报告');
  String get preparingReport => _('Preparing the report…', '正在生成报告…');
  String get reportFailed => _('The report couldn\'t be created. Please try again.', '报告生成失败，请重试。');

  // ---- overview -----------------------------------------------------------
  String analysedOn(String day, String time) => _('Analysed $day at $time', '分析于 $day $time');
  String get rows => _('Rows', '行数');
  String get columns => _('Columns', '列数');
  String get fixesApplied => _('Checks flagged', '检查项');
  String get charts => _('Charts', '图表');
  String get whatDataSays => _('What the data says', '数据说明了什么');
  String get noSummary => _('No summary was produced for this dataset.', '这份数据没有生成摘要。');
  String get writtenAutomatically =>
      _('Written automatically from your data. Check key figures before relying on them.', '根据你的数据自动生成，重要数字请自行核对。');
  String prepared(int n) => _('$n prepared', '共 $n 张');
  String get haveQuestion => _('Have a specific question?', '有具体问题？');
  String get haveQuestionHint => _('Ask in your own words, for example "where can I cut costs?"', '直接用你自己的话问，比如"哪里可以节省成本？"');
  String get reviewData => _('Review the data', '查看数据');
  String get askQuestion => _('Ask a question', '提个问题');
  String get seeCashFlow => _('See cash flow', '查看现金流');
  String privacyLine(int names, String others) => names == 0 && others.isEmpty
      ? _('No personal details were found in this file.', '文件中未发现个人信息。')
      : _('Hidden from the AI: ${[if (names > 0) '$names names', if (others.isNotEmpty) others].join(', ')}. Your answers still show the real values.',
          '已对 AI 隐藏：${[if (names > 0) '$names 个名称', if (others.isNotEmpty) others].join('，')}。你看到的回答仍显示真实信息。');
  String piiKind(String kind, int n) => switch (kind) {
        'phone' => _('$n phone numbers', '$n 个电话号码'),
        'email' => _('$n emails', '$n 个邮箱'),
        'id' => _('$n ID numbers', '$n 个证件号码'),
        'card' => _('$n card numbers', '$n 个银行卡号'),
        _ => '$n $kind',
      };
  String get privacyTitle => _('Privacy', '隐私保护');

  // ---- cash flow ----------------------------------------------------------
  String get cashTitle => _('Cash flow', '现金流');
  String cashPeriod(String from, String to, int months) =>
      _('$from to $to · $months months of transactions', '$from 至 $to · 共 $months 个月的交易');
  String get moneyIn => _('Money in', '收入');
  String get moneyOut => _('Money out', '支出');
  String get net => _('Net', '净额');
  String get perMonthRecent => _('a month, last 3 months', '每月，近3个月');
  String get cashNow => _('Cash in the bank', '账户现金');
  String get runway => _('Runway', '现金可维持');
  String runwayMonths(String m) => _('$m months', '$m 个月');
  String get runwayNotBurning => _('Not burning cash', '没有消耗现金');
  String get runwayUnknown => _('Enter your cash balance', '请输入现金余额');
  String get fromStatement => _('from the statement\'s last balance', '来自流水的最后余额');
  String get youEntered => _('as you entered it', '你输入的金额');
  String get updateCash => _('Update', '更新');
  String get cashOnHandLabel => _('Cash in the bank today', '今天账户中的现金');
  String get cashOnHandHelp => _('Runway and the projection use this figure.', '现金可维持时间和预测都基于这个数字。');
  String get monthlyInOut => _('Money in and out by month', '每月收支');
  String get projectionTitle => _('Cash balance, next 90 days', '未来90天现金余额');
  String get projectionCaption => _('Line is the likely path; shaded area is the range we\'d expect 8 times in 10.',
      '线条为最可能的走势，阴影为十次中有八次会落入的范围。');
  String get likelyPath => _('Likely', '最可能');
  String get likelyRange => _('Likely range', '可能范围');
  String get recorded => _('Recorded', '实际');
  String get today => _('Today', '今天');
  String gapAlertTitle(bool likely) => likely ? _('Cash is likely to run out', '现金很可能耗尽') : _('Cash could run short', '现金可能不足');
  String gapAlertBody(String date, int weeks, String amount) => _(
      'At the current rate the balance falls below zero around $date, about $weeks weeks from the end of the data. '
          'About $amount would cover the next 90 days even in a weaker month.',
      '按目前的速度，余额约在 $date 跌破零，距数据截止约 $weeks 周。准备约 $amount 即可覆盖未来90天，即使遇到较差的月份。');
  String get noGapTitle => _('No cash gap in the next 90 days', '未来90天没有资金缺口');
  String get noGapBody => _('Even in a weaker month the projected balance stays above zero.', '即使遇到较差的月份，预计余额也会保持为正。');
  String get seeOptions => _('See options', '查看可选方案');
  String get whereMoneyGoes => _('Where the money goes', '钱花在哪里');
  String get whereMoneyComes => _('Where the money comes from', '钱从哪里来');
  String get last90 => _('last 90 days', '近90天');
  String get trendWorsening => _('Getting worse: recent months are weaker than earlier ones.', '在变差：最近几个月比之前差。');
  String get trendImproving => _('Improving: recent months are stronger than earlier ones.', '在改善：最近几个月比之前好。');
  String get trendSteady => _('Steady: no big change across the period.', '平稳：整个期间没有大的变化。');
  String get inflowOnlyTitle => _('Sales only', '仅有销售数据');
  String get inflowOnlyBody => _(
      'This file only has money coming in, so runway and a cash-gap warning can\'t be worked out. Upload a bank '
          'statement or a file that includes costs to see them.',
      '这个文件只有收入，无法计算现金可维持时间和缺口预警。上传银行流水或包含支出的文件即可查看。');
  String get notDetectedTitle => _('No cash flow in this file', '这个文件没有现金流数据');
  String get notDetectedBody => _(
      'Cash flow needs a date and an amount on each row, like a bank statement or a sales ledger. '
          'Try the bakery sample to see what this page shows.',
      '现金流需要每一行都有日期和金额，例如银行流水或销售台账。可以打开烘焙店示例看看这个页面的效果。');

  // ---- financing ----------------------------------------------------------
  String get financingTitle => _('Ways to cover the gap', '弥补缺口的方式');
  String get financingLead => _(
      'Matched to your numbers, best fit first. These are kinds of financing, not specific products; '
          'costs are indicative ranges for China and real offers vary.',
      '根据你的数据匹配，最合适的排在前面。这里介绍的是融资类型，不是具体产品；成本为中国市场的参考范围，实际报价会有不同。');
  String get fitGood => _('Good fit', '较合适');
  String get fitPossible => _('Possible', '可以考虑');
  String get fitUnlikely => _('Unlikely fit', '不太合适');
  String get typicalCost => _('Typical cost', '常见成本');
  String get speed => _('Speed', '到账速度');
  String get goodFor => _('Good for', '适合');
  String get watchOut => _('Watch out', '注意');
  String get whyThisFits => _('Why it fits', '为什么匹配');
  String get calculator => _('Cost calculator', '成本计算');
  String get amount => _('Amount', '金额');
  String get months => _('Months', '月数');
  String get annualRate => _('Annual rate', '年化利率');
  String get totalInterest => _('Interest and fees', '利息和费用');
  String get monthlyRepayment => _('Monthly repayment', '每月还款');
  String calcNote(String rate) =>
      _('Equal monthly repayments at $rate a year. Ask lenders for the APR to compare offers fairly.', '按年化 $rate 等额本息计算。比较报价时请向机构索要年化利率。');
  String get notAdvice => _(
      'For information only, not financial advice. Check terms with a licensed lender before deciding.',
      '仅供参考，不构成金融建议。做决定前请向持牌金融机构确认条款。');
  String reason(String code) => switch (code) {
        'burn' => _('You are spending more than you earn each month.', '你每月的支出超过收入。'),
        'supplier_share' => _('Suppliers are one of your largest costs.', '供应商货款是你最大的支出之一。'),
        'invoice_income' => _('You have business customers who pay invoices.', '你有按发票付款的企业客户。'),
        'no_invoices' => _('No invoice income found in this data.', '数据中没有发现发票收入。'),
        'invoice_small' => _('Invoice income is small next to the amount needed, so this can only cover part of it.',
            '发票收入相对所需金额较少，只能覆盖一部分。'),
        'ongoing_losses' => _('Losses are growing, so credit would only delay the problem unless costs or sales change.',
            '亏损在扩大，除非调整成本或提升销售，否则授信只会推迟问题。'),
        'history_ok' => _('You have at least 6 months of records.', '你有至少6个月的经营记录。'),
        'short_history' => _('Less than 6 months of records; lenders may ask for more.', '经营记录不足6个月，银行可能要求更多材料。'),
        'size_ok' => _('The amount is modest compared with your monthly income.', '所需金额相对你的月收入不算大。'),
        'large_need' => _('The amount is large compared with your monthly income.', '所需金额相对你的月收入偏大。'),
        'short_term_gap' => _('The gap is short-term, which flexible credit suits.', '缺口是短期的，适合灵活的授信。'),
        'platform_income' => _('Much of your income comes through payment platforms.', '你的大部分收入通过支付平台收款。'),
        'no_platform_income' => _('Little income through payment platforms.', '通过支付平台的收入很少。'),
        'high_cost' => _('Usually the most expensive option here.', '通常是这里成本最高的方式。'),
        _ => code,
      };

  // ---- data ---------------------------------------------------------------
  String get dataTitle => _('Columns and checks', '列与检查');
  String get dataLead => _('What each column holds, and exactly what was checked or changed before analysis. '
          'Your original file is never modified.',
      '每一列的含义，以及分析前检查或修改了什么。你的原始文件不会被改动。');
  String get columnsHeading => _('Columns', '列');
  String nColumns(int n) => _('$n columns', '$n 列');
  String get colColumn => _('Column', '列名');
  String get colMeaning => _('What it means', '含义');
  String get colType => _('Type', '类型');
  String get colNotes => _('Notes', '备注');
  String get noDictionary => _('No column descriptions were produced.', '没有生成列说明。');
  String get changesHeading => _('Checks before analysis', '分析前的检查');
  String nChanges(int n) => _('$n items', '$n 项');
  String get noChanges => _('No changes were needed. The data came in clean.', '无需任何修改，数据很干净。');
  String housekeeping(int n) =>
      _('Plus $n storage optimisation${n == 1 ? '' : 's'} that don\'t change any values.', '另有 $n 项存储优化，不改变任何数值。');
  String action(String code) => switch (code) {
        'coerce_datetime' => _('Read as dates', '识别为日期'),
        'strip_currency_and_cast_float' => _('Removed currency symbols', '去除货币符号'),
        'drop_zero_variance' => _('Removed, same value in every row', '已移除（每行数值相同）'),
        'flag_high_cardinality_id' => _('Set aside as an identifier', '作为标识列，不参与分析'),
        'convert_to_category' => _('Treated as categories', '按类别处理'),
        'impute_missing_numeric' => _('Filled missing numbers', '填补缺失数值'),
        'impute_missing_categorical' => _('Filled missing labels', '填补缺失标签'),
        'cap_outliers_iqr' => _('Capped extreme values', '截断极端值'),
        'flag_outliers_iqr' => _('Unusual values found, kept as they are', '发现异常值，已保留原值'),
        'downcast_float64' || 'downcast_int64' => _('Stored more compactly', '压缩存储'),
        _ => code.replaceAll('_', ' '),
      };

  // ---- ask ----------------------------------------------------------------
  String get askEyebrow => _('Ask', '提问');
  String askTitle(String name) => _('Ask about $name', '关于「$name」提问');
  String get askLead => _(
      'Each answer is worked out from your data: MyAnalyst writes the analysis, runs it, and fixes it if it fails. '
          'You can always see the code it used.',
      '每个回答都基于你的数据：MyAnalyst 编写分析代码、运行，失败时自动修正。你随时可以查看它使用的代码。');
  String get tryThese => _('TRY ONE OF THESE', '试试这些问题');
  String youAsked(String t) => _('You asked · $t', '你的提问 · $t');
  List<String> get workingPhases => zh
      ? const ['正在规划分析', '正在编写代码', '正在沙箱中运行', '正在核对结果']
      : const ['Planning the analysis', 'Writing the code', 'Running it in the sandbox', 'Checking the result'];
  String get couldntAnswer => _('Couldn\'t answer this one', '这个问题暂时无法回答');
  String triedTimes(int n) => _(
      'MyAnalyst tried $n times but the analysis didn\'t run successfully. Try asking something narrower, '
          'for example about one column or one time period.',
      'MyAnalyst 尝试了 $n 次，但分析没有成功运行。可以把问题缩小一些，比如只问某一列或某段时间。');
  String get result => _('Result', '结果');
  String get fixedTooltip => _('The first version of the analysis failed, so MyAnalyst read the error and rewrote it.',
      '第一版分析运行失败，MyAnalyst 读取错误后重写了代码。');
  String fixedTimes(int n) => n == 1 ? _('Fixed its own code once', '自动修正了1次代码') : _('Fixed its own code $n times', '自动修正了$n次代码');
  String get showCode => _('Show the code', '查看代码');
  String get hideCode => _('Hide the code', '收起代码');
  String get codeCaption => _('Python · ran in the sandbox', 'Python · 在沙箱中运行');
  String get copyCode => _('Copy code', '复制代码');
  String get codeCopied => _('Code copied', '代码已复制');
  String get workingOnLast => _('Working on your last question…', '正在处理上一个问题…');
  String askHint(String file) => _('Ask a question about $file', '就 $file 提问');
  String get askButton => _('Ask', '提问');
  String get answersDisclaimer => _('Answers are generated automatically from your data. Check important figures before acting on them.',
      '回答由系统根据你的数据自动生成，做决定前请核对重要数字。');
  String get answersDisclaimerShort => _('Answers are generated automatically. Check important figures.', '回答为自动生成，请核对重要数字。');

  // ---- rules --------------------------------------------------------------
  String get rulesEyebrow => _('Rules', '规则');
  String get rulesTitle => _('House rules', '分析规则');
  String get rulesLead => _('Standing instructions MyAnalyst follows in every answer. Write them the way you would brief '
          'a new analyst on their first day.',
      'MyAnalyst 在每次回答中都会遵守的长期规则。就像给新同事做入职说明一样写下来。');
  String get addRule => _('Add a rule', '添加规则');
  String get addRuleButton => _('Add rule', '添加');
  String get adding => _('Adding…', '添加中…');
  String get rulesCantEdit => _('Rules can\'t be edited or removed yet.', '规则暂时无法编辑或删除。');
  String get examples => _('EXAMPLES', '示例');
  List<String> get ruleExamples => zh
      ? const ['计算收入时不包括退款和作废订单。', '我们的财年从4月1日开始。', '金额以人民币为单位，四舍五入到整数。']
      : const [
          'Exclude refunds and voided sales from revenue figures.',
          'Our financial year starts on 1 April.',
          'Report money in yuan, rounded to whole numbers.',
        ];
  String get currentRules => _('Current rules', '当前规则');
  String get noRules => _('No rules yet. Answers will use sensible defaults until you add some.', '还没有规则。在添加之前，回答会使用合理的默认设置。');
  String get retry => _('Retry', '重试');
  String added(String t) => _('Added $t', '添加于 $t');
  String get ruleAdded => _('Rule added. It applies to every answer from now on.', '规则已添加，之后的每个回答都会遵守。');
  String get ruleTooShort => _('Write the rule as a short sentence.', '请用一句简短的话写下规则。');
  String ruleTooLong(int n) => _('Keep rules under $n characters.', '规则请少于 $n 个字符。');

  // ---- charts -------------------------------------------------------------
  String get capHistogram => _('How often each value occurs', '各数值出现的频率');
  String capRanked(int n) => n == 1 ? _('1 group', '1 组') : _('Ranked, $n groups', '排序，共 $n 组');
  String capPoints(String n) => _('$n points', '$n 个点');
  String get capForecast => _('Recorded values and the projection ahead', '实际数值与未来预测');
  String get capOverTime => _('Over time', '随时间变化');
  String get capBox => _('Spread of values in each group', '各组数值的分布');
  String get capNA => _('Not available', '暂不可用');
  String showAll(int n) => _('Show all $n', '显示全部 $n 项');
  String showTop(int n) => _('Show top $n', '只显示前 $n 项');
  String get projection => _('Projection', '预测');
  String get boxHelp => _('Box shows the middle half of values; the line inside is the median. Number on the right is the median.',
      '方框表示中间一半的数值，框内竖线为中位数，右侧数字为中位数。');
  String get noValues => _('No values to show.', '没有可显示的数值。');
  String get chartUnavailable => _('This chart could not be generated for this dataset.', '无法为这份数据生成此图表。');
  String modelNote(String model) => _('Model: $model. Shaded area is the likely range.', '模型：$model。阴影为可能范围。');
}
