/// 图标映射：把持久化的图标名转换成 Material 图标。
///
/// 单独成文件是为了让 domain 层保持无 Flutter 依赖。
library;

import 'package:flutter/material.dart';

/// 图标名 → 图标。
IconData iconForName(String? name, {IconData fallback = Icons.label_outline}) {
  switch (name) {
    case 'cash':
      return Icons.payments_outlined;
    case 'bank':
      return Icons.account_balance_outlined;
    case 'alipay':
      return Icons.account_balance_wallet_outlined;
    case 'wechat':
      return Icons.chat_bubble_outline;
    case 'credit_card':
      return Icons.credit_card;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'transport':
      return Icons.directions_bus_outlined;
    case 'shopping':
      return Icons.shopping_bag_outlined;
    case 'home':
      return Icons.home_outlined;
    case 'phone':
      return Icons.smartphone_outlined;
    case 'game':
      return Icons.sports_esports_outlined;
    case 'medical':
      return Icons.local_hospital_outlined;
    case 'book':
      return Icons.menu_book_outlined;
    case 'gift':
      return Icons.card_giftcard_outlined;
    case 'more':
      return Icons.more_horiz;
    case 'salary':
      return Icons.attach_money;
    case 'bonus':
      return Icons.emoji_events_outlined;
    case 'work':
      return Icons.work_outline;
    case 'trending_up':
      return Icons.trending_up;
    case 'red_packet':
      return Icons.redeem_outlined;
    // 以下为分类图标选择器额外提供的常用图标。
    case 'coffee':
      return Icons.local_cafe_outlined;
    case 'fastfood':
      return Icons.lunch_dining_outlined;
    case 'grocery':
      return Icons.local_grocery_store_outlined;
    case 'taxi':
      return Icons.local_taxi_outlined;
    case 'flight':
      return Icons.flight_takeoff_outlined;
    case 'train':
      return Icons.train_outlined;
    case 'fuel':
      return Icons.local_gas_station_outlined;
    case 'car':
      return Icons.directions_car_outlined;
    case 'clothes':
      return Icons.checkroom_outlined;
    case 'cosmetics':
      return Icons.spa_outlined;
    case 'baby':
      return Icons.child_friendly_outlined;
    case 'pet':
      return Icons.pets_outlined;
    case 'fitness':
      return Icons.fitness_center_outlined;
    case 'movie':
      return Icons.local_movies_outlined;
    case 'music':
      return Icons.music_note_outlined;
    case 'travel':
      return Icons.beach_access_outlined;
    case 'hotel':
      return Icons.hotel_outlined;
    case 'water':
      return Icons.water_drop_outlined;
    case 'power':
      return Icons.bolt_outlined;
    case 'internet':
      return Icons.wifi_outlined;
    case 'insurance':
      return Icons.shield_outlined;
    case 'tax':
      return Icons.receipt_long_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'computer':
      return Icons.computer_outlined;
    case 'certificate':
      return Icons.workspace_premium_outlined;
    case 'charity':
      return Icons.volunteer_activism_outlined;
    case 'party':
      return Icons.celebration_outlined;
    case 'transfer':
      return Icons.swap_horiz;
    case 'refund':
      return Icons.currency_exchange_outlined;
    case 'stock':
      return Icons.show_chart;
    case 'rent':
      return Icons.apartment_outlined;
    default:
      return fallback;
  }
}

/// 可选图标的展示项：给人看的名字 + 实际图标。
class IconChoice {
  /// 构造。
  const IconChoice(this.name, this.label, this.icon);

  /// 持久化用的图标名（与 [iconForName] 的 key 一致）。
  final String name;

  /// 中文名称，用于无障碍语义与提示。
  final String label;

  /// 实际图标。
  final IconData icon;
}

/// 分类图标选择器的可选集合。
///
/// 刻意只提供受控集合而不是让用户自由输入：图标名要能映射到具体 IconData，
/// 自由输入会立刻踩到「名字对不上 → 显示成默认图标」的问题。
const List<IconChoice> kCategoryIconChoices = <IconChoice>[
  IconChoice('restaurant', '餐饮', Icons.restaurant_outlined),
  IconChoice('fastfood', '快餐', Icons.lunch_dining_outlined),
  IconChoice('coffee', '咖啡饮品', Icons.local_cafe_outlined),
  IconChoice('grocery', '买菜', Icons.local_grocery_store_outlined),
  IconChoice('transport', '公交地铁', Icons.directions_bus_outlined),
  IconChoice('taxi', '打车', Icons.local_taxi_outlined),
  IconChoice('car', '私家车', Icons.directions_car_outlined),
  IconChoice('fuel', '加油', Icons.local_gas_station_outlined),
  IconChoice('train', '火车', Icons.train_outlined),
  IconChoice('flight', '机票', Icons.flight_takeoff_outlined),
  IconChoice('shopping', '购物', Icons.shopping_bag_outlined),
  IconChoice('clothes', '服饰', Icons.checkroom_outlined),
  IconChoice('cosmetics', '美妆', Icons.spa_outlined),
  IconChoice('home', '居住', Icons.home_outlined),
  IconChoice('rent', '房租', Icons.apartment_outlined),
  IconChoice('water', '水电', Icons.water_drop_outlined),
  IconChoice('power', '电费', Icons.bolt_outlined),
  IconChoice('internet', '网络', Icons.wifi_outlined),
  IconChoice('phone', '通讯', Icons.smartphone_outlined),
  IconChoice('game', '游戏', Icons.sports_esports_outlined),
  IconChoice('movie', '影音', Icons.local_movies_outlined),
  IconChoice('music', '音乐', Icons.music_note_outlined),
  IconChoice('travel', '旅行', Icons.beach_access_outlined),
  IconChoice('hotel', '住宿', Icons.hotel_outlined),
  IconChoice('fitness', '运动健身', Icons.fitness_center_outlined),
  IconChoice('medical', '医疗', Icons.local_hospital_outlined),
  IconChoice('insurance', '保险', Icons.shield_outlined),
  IconChoice('book', '书籍', Icons.menu_book_outlined),
  IconChoice('school', '学费', Icons.school_outlined),
  IconChoice('computer', '数码', Icons.computer_outlined),
  IconChoice('baby', '母婴', Icons.child_friendly_outlined),
  IconChoice('pet', '宠物', Icons.pets_outlined),
  IconChoice('gift', '礼物', Icons.card_giftcard_outlined),
  IconChoice('party', '聚会', Icons.celebration_outlined),
  IconChoice('charity', '公益', Icons.volunteer_activism_outlined),
  IconChoice('tax', '税费', Icons.receipt_long_outlined),
  IconChoice('salary', '工资', Icons.attach_money),
  IconChoice('bonus', '奖金', Icons.emoji_events_outlined),
  IconChoice('work', '兼职', Icons.work_outline),
  IconChoice('certificate', '证书', Icons.workspace_premium_outlined),
  IconChoice('trending_up', '理财收益', Icons.trending_up),
  IconChoice('stock', '股票基金', Icons.show_chart),
  IconChoice('red_packet', '红包', Icons.redeem_outlined),
  IconChoice('refund', '退款', Icons.currency_exchange_outlined),
  IconChoice('transfer', '转账', Icons.swap_horiz),
  IconChoice('more', '其他', Icons.more_horiz),
];

/// 图标名是否在受控集合内。
bool isKnownCategoryIcon(String? name) {
  if (name == null) {
    return false;
  }
  return kCategoryIconChoices.any((IconChoice c) => c.name == name);
}

/// 分类可选配色（每种都经过挑选，保证浅色底 + 深色图标/文字的对比度足够）。
const List<String> kCategoryColorChoices = <String>[
  '#FF7043',
  '#D98C1F',
  '#FFA726',
  '#FDD835',
  '#9CCC65',
  '#1F9D55',
  '#26A69A',
  '#42A5F5',
  '#2F6FED',
  '#5C6BC0',
  '#7E57C2',
  '#AB47BC',
  '#EC407A',
  '#E53935',
  '#8D6E63',
  '#90A4AE',
];

/// 该颜色是否偏浅（浅色底需要把图标/文字压深一点才看得清）。
bool isLightColor(Color color) {
  // 使用 sRGB 相对亮度的简化算法（0-1），阈值 0.6 偏保守。
  final double luminance = 0.299 * (color.r * 255) +
      0.587 * (color.g * 255) +
      0.114 * (color.b * 255);
  return luminance > 150;
}

/// 给浅色底配一个可读的前景色。
Color readableOn(Color background) =>
    isLightColor(background) ? const Color(0xFF37474F) : Colors.white;

/// 把 `#RRGGBB` 解析为 Color，失败返回 null。
Color? colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) {
    return null;
  }
  String value = hex.replaceFirst('#', '');
  if (value.length == 6) {
    value = 'FF$value';
  }
  final int? parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
