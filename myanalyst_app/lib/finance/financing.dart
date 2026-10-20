// Plain-language catalogue of financing options, in English and Chinese.
//
// The backend decides *fit* from the business's own numbers
// (cashflow.financing_fit); this file holds what each option is, what it
// typically costs and what to watch out for. Costs are indicative ranges
// for mainland China, for education only: not offers, not advice.

import 'dart:math' as math;

import '../i18n/strings.dart';

class FinancingOption {
  const FinancingOption({
    required this.key,
    required this.name,
    required this.what,
    required this.cost,
    required this.speed,
    required this.goodFor,
    required this.watchOut,
    required this.defaultRate,
  });

  final String key;
  final String name;
  final String what;
  final String cost;
  final String speed;
  final String goodFor;
  final String watchOut;

  /// Midpoint annual rate used to pre-fill the calculator; 0 = no interest.
  final double defaultRate;
}

FinancingOption financingOption(String key, S s) {
  final zh = s.zh;
  return switch (key) {
    'cost_actions' => FinancingOption(
        key: key,
        name: zh ? '先削减或推迟支出' : 'Cut or delay costs first',
        what: zh
            ? '不借钱也能缩小缺口：按实际销量调整采购、优化排班、推迟非必要支出。'
            : 'Close part of the gap without borrowing: order to match sales, adjust staffing, postpone non-essential spending.',
        cost: zh ? '无利息' : 'No interest',
        speed: zh ? '立即' : 'Immediate',
        goodFor: zh ? '任何持续亏损的情况，应与其他方式一起使用。' : 'Any business losing money each month; use alongside the options below.',
        watchOut: zh ? '不要削减带来销售的开支，比如核心员工和主力产品。' : 'Don\'t cut what brings in sales, such as key staff or best-selling stock.',
        defaultRate: 0,
      ),
    'supplier_credit' => FinancingOption(
        key: key,
        name: zh ? '延长供应商账期' : 'Longer supplier payment terms',
        what: zh
            ? '与主要供应商协商延后付款，例如从30天延长到60天，相当于一笔无息短期周转。'
            : 'Agree with your main suppliers to pay later, for example 60 days instead of 30. It works like a short, interest-free loan.',
        cost: zh ? '通常免费；放弃提前付款折扣约相当于每月2%' : 'Often free; giving up an early-payment discount can cost ~2% a month',
        speed: zh ? '几天' : 'Days',
        goodFor: zh ? '原料或库存采购占比较大的企业。' : 'Businesses where stock or ingredients are a large share of costs.',
        watchOut: zh ? '要按约定付款，否则会影响合作关系和供货。' : 'Pay on the new dates, or you risk the relationship and your supply.',
        defaultRate: 0,
      ),
    'invoice_finance' => FinancingOption(
        key: key,
        name: zh ? '应收账款融资' : 'Invoice (receivables) financing',
        what: zh
            ? '把企业客户尚未支付的发票作为依据，提前从银行或保理机构拿到大部分款项。'
            : 'Get most of the money from unpaid invoices now, from a bank or factoring company, instead of waiting for business customers to pay.',
        cost: zh ? '年化约4%–10%，另有手续费' : 'About 4%–10% a year, plus fees',
        speed: zh ? '1–2周' : '1–2 weeks',
        goodFor: zh ? '有按发票付款的企业客户。' : 'Businesses with customers who pay invoices on terms.',
        watchOut: zh ? '额度取决于客户的信用；客户逾期可能由你承担。' : 'The limit depends on your customers\' credit; you may carry the risk if they pay late.',
        defaultRate: 0.07,
      ),
    'bank_loan' => FinancingOption(
        key: key,
        name: zh ? '银行普惠小微贷款' : 'Bank small-business loan',
        what: zh
            ? '银行面向小微企业的经营贷款，按期还本付息，通常是成本最低的借款方式。'
            : 'A term loan from a bank\'s small-business programme, repaid in instalments. Usually the cheapest way to borrow.',
        cost: zh ? '年化约3.5%–6%' : 'About 3.5%–6% a year',
        speed: zh ? '1–4周' : '1–4 weeks',
        goodFor: zh ? '经营记录完整、需要几个月资金周转的企业。' : 'Businesses with a solid record that need cover for several months.',
        watchOut: zh ? '可能需要纳税记录、流水和担保；要为审批时间留出余量。' : 'Expect to show tax records and statements, and possibly a guarantee. Allow time for approval.',
        defaultRate: 0.045,
      ),
    'credit_line' => FinancingOption(
        key: key,
        name: zh ? '循环授信额度' : 'Revolving credit line',
        what: zh
            ? '银行给出一个额度，需要时随借随还，只为实际使用的部分付息。'
            : 'A limit you can draw on and repay as needed, paying interest only on what you use.',
        cost: zh ? '年化约4%–8%（仅按使用部分）' : 'About 4%–8% a year on what you use',
        speed: zh ? '审批1–3周，之后随时可用' : '1–3 weeks to set up, then instant',
        goodFor: zh ? '短期或季节性的资金缺口。' : 'Short or seasonal gaps.',
        watchOut: zh ? '银行可能调低额度；不要用它弥补长期亏损。' : 'Banks can reduce the limit; don\'t use it to fund ongoing losses.',
        defaultRate: 0.06,
      ),
    'platform_loan' => FinancingOption(
        key: key,
        name: zh ? '支付平台经营贷' : 'Payment-platform business loan',
        what: zh
            ? '收款平台根据你的流水提供的快速贷款，通常从每日收款中自动扣还。'
            : 'A fast loan offered by your payment platform based on your takings, often repaid automatically from daily sales.',
        cost: zh ? '年化约7%–18%或更高' : 'About 7%–18% a year or more',
        speed: zh ? '几分钟到几天' : 'Minutes to days',
        goodFor: zh ? '急需小额资金、等不了银行审批。' : 'Small, urgent needs when you can\'t wait for a bank.',
        watchOut: zh ? '成本高；每日扣款会进一步挤压现金流。务必比较年化利率。' : 'Expensive, and daily deductions squeeze cash further. Always compare the annual rate.',
        defaultRate: 0.12,
      ),
    _ => FinancingOption(
        key: key, name: key, what: '', cost: '', speed: '', goodFor: '', watchOut: '', defaultRate: 0.06),
  };
}

/// Equal monthly instalments (annuity). Returns (monthly payment, total interest).
(double, double) repaymentCost(double principal, double annualRate, int months) {
  if (principal <= 0 || months <= 0) return (0, 0);
  if (annualRate <= 0) return (principal / months, 0);
  final r = annualRate / 12;
  final payment = principal * r / (1 - math.pow(1 + r, -months));
  return (payment, payment * months - principal);
}
