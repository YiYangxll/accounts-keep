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
    default:
      return fallback;
  }
}

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
