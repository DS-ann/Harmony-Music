import '../utils/platform_utils.dart';

/// Reads the artwork URL out of a `thumbnails` field, tolerating every shape it
/// takes in practice: missing, null, an empty list, a list of non-maps, and — as
/// written by cloud syncs from builds whose payload sanitizer stripped every
/// `url` including artwork ones — a list holding an empty map. Returns null when
/// there is no usable URL so callers can pick their own fallback; reading
/// `json['thumbnails'][0]['url']` directly throws on all of those.
String? thumbnailUrlFromJson(dynamic json) {
  if (json is! Map) return null;
  final thumbnails = json['thumbnails'];
  if (thumbnails is! List || thumbnails.isEmpty) return null;
  final first = thumbnails.first;
  if (first is! Map) return null;
  final url = first['url'];
  if (url is! String || url.isEmpty) return null;
  return url;
}

class Thumbnail {
  Thumbnail(this._url);
  final String _url;
  String sizewith(int size) => (_url.contains("-rj"))
      ? "${_url.split("=")[0]}=w$size-h$size-l90-rj"
      : (_url.contains("=s"))
      ? "${_url.split("=s")[0]}=s$size"
      : (_url.contains("i.yti") && size >= 600)
      ? url.replaceFirst("sddefault", "maxresdefault")
      : url;
  String get url => _url;
  String get high => sizewith(400); //450
  String get medium => sizewith(250); //350
  String get low => sizewith(150);
  String get extraHigh => isDesktopPlatform ? sizewith(1000) : sizewith(600);
}
