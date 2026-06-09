final Map<String, String> _stickerEmojiMap = {
  '捂脸': '🤦',
  '笑哭': '😂',
  '偷笑': '🤭',
  '赞': '👍',
  '鼓掌': '👏',
  '送花': '🌹',
  '爱慕': '😍',
  '爽': '😎',
  '没看够': '🥹',
  '笑': '😄',
  '探究': '🧐',
  '尬笑': '😅',
  '吃瓜': '🍉',
  '奸笑': '😏',
  '大笑': '😆',
  '什么': '😮',
  '撇嘴': '😒',
  '思考': '🤔',
  '怒': '😡',
  '震惊': '😱',
  '微笑': '🙂',
  '酷': '😎',
  '抓狂': '😫',
  '盯': '👀',
  '快哭了': '🥹',
  '哭': '😭',
  '恐惧': '😨',
  '舔屏': '😍',
  '你细品': '🤔',
  '害羞': '😊',
  '送心': '💖',
  '石化': '🗿',
  'KISS': '😘',
};

final RegExp _danmakuStickerPattern = RegExp(r'\[([^\[\]]{1,16})\]');

String normalizeDanmakuDisplayText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return raw;

  final matches =
      _danmakuStickerPattern.allMatches(text).toList(growable: false);
  if (matches.isEmpty) return raw;

  final onlyStickers =
      text.replaceAll(_danmakuStickerPattern, '').trim().isEmpty;
  if (onlyStickers) {
    return matches
        .map((match) => _emojiForToken(match.group(1) ?? ''))
        .join(' ');
  }

  return text.replaceAllMapped(_danmakuStickerPattern, (match) {
    return _emojiForToken(match.group(1) ?? '');
  });
}

String _emojiForToken(String rawToken) {
  final token = rawToken.trim();
  if (token.isEmpty) return '✨';
  final mapped = _stickerEmojiMap[token];
  if (mapped != null) return mapped;

  if (token.contains('赞')) return '👍';
  if (token.contains('花')) return '🌹';
  if (token.contains('送心') || token.contains('心')) return '💖';
  if (token.contains('爱') || token.contains('慕')) return '😍';
  if (token.contains('捂脸') || token.contains('脸')) return '🤦';
  if (token.contains('笑')) return '😂';
  if (token.contains('哭')) return '😭';
  if (token.contains('怒')) return '😡';
  if (token.contains('惊')) return '😱';
  if (token.contains('探') || token.contains('思') || token.contains('品')) {
    return '🤔';
  }
  if (token.contains('酷') || token.contains('爽')) return '😎';
  if (token.contains('瓜')) return '🍉';
  if (token.contains('鼓')) return '👏';
  if (token.contains('盯')) return '👀';
  if (token.contains('羞')) return '😊';
  if (token.contains('吻')) return '😘';
  return '✨';
}
