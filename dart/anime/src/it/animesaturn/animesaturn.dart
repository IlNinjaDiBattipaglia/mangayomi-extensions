import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class AnimeSaturn extends MProvider {
  AnimeSaturn({required this.source});

  MSource source;

  final Client client = Client();

  @override
  Map<String, String> getHeaders(String url) {
    return {
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      "Referer": "${source.baseUrl}/",
    };
  }

  @override
  Future<MPages> getPopular(int page) async {
    final res = (await client.get(
      Uri.parse("${source.baseUrl}/ongoing/$page"),
      headers: getHeaders("${source.baseUrl}/ongoing/$page"),
    )).body;

    List<MManga> animeList = [];

    // Estrazione flessibile tramite parser HTML se l'XPath fallisce su Cloudflare
    final doc = parseHtml(res);
    final elements = doc.select("div.sebox, div.card, div.item-archivio");

    if (elements.isNotEmpty) {
      for (var element in elements) {
        final aTag = element.selectFirst("a");
        final imgTag = element.selectFirst("img");
        final title = aTag?.attr("title") ?? aTag?.text ?? "";
        final link = aTag?.attr("href") ?? "";
        final img = imgTag?.attr("src") ?? "";

        if (title.isNotEmpty && link.isNotEmpty) {
          MManga anime = MManga();
          anime.name = formatTitle(title);
          anime.imageUrl = img;
          anime.link = link;
          animeList.add(anime);
        }
      }
    }

    // Fallback XPath originale se il selettor CSS è vuoto
    if (animeList.isEmpty) {
      final urls = xpath(res, '//div[contains(@class, "card")]/a/@href');
      var names = xpath(res, '//div[contains(@class, "card")]/a/@title');
      if (names.isEmpty) {
        names = xpath(res, '//div[contains(@class, "card")]/a/text()');
      }
      final images = xpath(res, '//div[contains(@class, "card")]/a/img/@src');

      for (var i = 0; i < names.length; i++) {
        MManga anime = MManga();
        anime.name = formatTitle(names[i]);
        anime.imageUrl = i < images.length ? images[i] : "";
        anime.link = i < urls.length ? urls[i] : "";
        if (anime.name.isNotEmpty && anime.link.isNotEmpty) {
          animeList.add(anime);
        }
      }
    }

    return MPages(animeList, animeList.isNotEmpty);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = (await client.get(
      Uri.parse("${source.baseUrl}/newest?page=$page"),
      headers: getHeaders("${source.baseUrl}/newest?page=$page"),
    )).body;

    List<MManga> animeList = [];
    final doc = parseHtml(res);
    final elements = doc.select("div.card");

    for (var element in elements) {
      final aTag = element.selectFirst("a");
      final imgTag = element.selectFirst("img");
      final title = aTag?.attr("title") ?? aTag?.text ?? "";
      final link = aTag?.attr("href") ?? "";
      final img = imgTag?.attr("src") ?? "";

      if (title.isNotEmpty && link.isNotEmpty) {
        MManga anime = MManga();
        anime.name = formatTitle(title);
        anime.imageUrl = img;
        anime.link = link;
        animeList.add(anime);
      }
    }

    return MPages(animeList, animeList.isNotEmpty);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final filters = filterList.filters;
    String url = "";

    if (query.isNotEmpty) {
      url = "${source.baseUrl}/animelist?search=$query";
    } else {
      url = "${source.baseUrl}/filter?";
      int variantgenre = 0;
      int variantstate = 0;
      int variantyear = 0;
      for (var filter in filters) {
        if (filter.type == "GenreFilter") {
          final genre = (filter.state as List).where((e) => e.state).toList();
          if (genre.isNotEmpty) {
            for (var st in genre) {
              url += "&categories%5B${variantgenre}%5D=${st.value}";
              variantgenre++;
            }
          }
        } else if (filter.type == "YearList") {
          final years = (filter.state as List).where((e) => e.state).toList();
          if (years.isNotEmpty) {
            for (var st in years) {
              url += "&years%5B${variantyear}%5D=${st.value}";
              variantyear++;
            }
          }
        } else if (filter.type == "StateList") {
          final states = (filter.state as List).where((e) => e.state).toList();
          if (states.isNotEmpty) {
            for (var st in states) {
              url += "&states%5B${variantstate}%5D=${st.value}";
              variantstate++;
            }
          }
        } else if (filter.type == "LangList") {
          final lang = filter.values[filter.state].value;
          if (lang.isNotEmpty) {
            url += "&language%5B0%5D=$lang";
          }
        }
      }
      url += "&page=$page";
    }

    final res = (await client.get(
      Uri.parse(url),
      headers: getHeaders(url),
    )).body;

    List<MManga> animeList = [];
    final doc = parseHtml(res);
    final elements = doc.select("div.item-archivio, div.card");

    for (var element in elements) {
      final aTag = element.selectFirst("a.badge-archivio, a");
      final imgTag = element.selectFirst("img");
      final title = aTag?.text ?? "";
      final link = aTag?.attr("href") ?? "";
      final img = imgTag?.attr("src") ?? "";

      if (title.isNotEmpty && link.isNotEmpty) {
        MManga anime = MManga();
        anime.name = formatTitle(title);
        anime.imageUrl = img;
        anime.link = link;
        animeList.add(anime);
      }
    }

    return MPages(animeList, query.isEmpty && animeList.isNotEmpty);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final statusList = [
      {"In corso": 0, "Finito": 1},
    ];

    final res = (await client.get(
      Uri.parse(url),
      headers: getHeaders(url),
    )).body;

    MManga anime = MManga();
    final doc = parseHtml(res);

    final description = doc.selectFirst("#full-trama")?.text ?? doc.selectFirst("#shown-trama")?.text ?? "";
    anime.description = description;

    final epElements = doc.select("a.episodi-link-button");
    List<MChapter> episodesList = [];

    for (var i = 0; i < epElements.length; i++) {
      MChapter episode = MChapter();
      episode.name = epElements[i].text.trim();
      episode.url = epElements[i].attr("href") ?? "";
      episodesList.add(episode);
    }

    anime.chapters = episodesList.reversed.toList();
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = (await client.get(
      Uri.parse(url),
      headers: getHeaders(url),
    )).body;

    final doc = parseHtml(res);
    final watchLink = doc.selectFirst("a[href*='/watch']")?.attr("href");

    if (watchLink == null || watchLink.isEmpty) return [];

    final resVid = (await client.get(
      Uri.parse(watchLink),
      headers: getHeaders(watchLink),
    )).body;

    String masterUrl = "";
    if (resVid.contains("jwplayer(")) {
      masterUrl = substringBefore(substringAfter(resVid, "file: \""), "\"");
    } else {
      final sourceTag = parseHtml(resVid).selectFirst("source");
      if (sourceTag != null) {
        masterUrl = sourceTag.attr("src") ?? "";
      }
    }

    if (masterUrl.isEmpty) return [];

    List<MVideo> videos = [];
    final streamHeaders = getHeaders(masterUrl);

    if (masterUrl.endsWith("playlist.m3u8")) {
      final masterPlaylistRes = (await client.get(
        Uri.parse(masterUrl),
        headers: streamHeaders,
      )).body;

      for (var it in substringAfter(
        masterPlaylistRes,
        "#EXT-X-STREAM-INF:",
      ).split("#EXT-X-STREAM-INF:")) {
        final quality =
            "${substringBefore(substringBefore(substringAfter(substringAfter(it, "RESOLUTION="), "x"), ","), "\n")}p";

        String videoUrl = substringBefore(substringAfter(it, "\n"), "\n");

        if (!videoUrl.startsWith("http")) {
          videoUrl =
              "${masterUrl.split("/").sublist(0, masterUrl.split("/").length - 1).join("/")}/$videoUrl";
        }

        MVideo video = MVideo();
        video
          ..url = videoUrl
          ..originalUrl = videoUrl
          ..headers = streamHeaders
          ..quality = quality;
        videos.add(video);
      }
    } else {
      MVideo video = MVideo();
      video
        ..url = masterUrl
        ..originalUrl = masterUrl
        ..headers = streamHeaders
        ..quality = "Qualità predefinita";
      videos.add(video);
    }
    return sortVideos(videos, source.id);
  }

  String formatTitle(String titlestring) {
    return titlestring
        .replaceAll("(ITA) ITA", "Dub ITA")
        .replaceAll("(ITA)", "Dub ITA")
        .replaceAll("Sub ITA", "")
        .trim();
  }

  @override
  List<dynamic> getFilterList() {
    return [
      HeaderFilter("Ricerca per titolo ignora i filtri e viceversa"),
      GroupFilter("GenreFilter", "Generi", [
        CheckBoxFilter("Arti Marziali", "Arti Marziali"),
        CheckBoxFilter("Avventura", "Avventura"),
        CheckBoxFilter("Azione", "Azione"),
        CheckBoxFilter("Bambini", "Bambini"),
        CheckBoxFilter("Commedia", "Commedia"),
        CheckBoxFilter("Demenziale", "Demenziale"),
        CheckBoxFilter("Demoni", "Demoni"),
        CheckBoxFilter("Drammatico", "Drammatico"),
        CheckBoxFilter("Ecchi", "Ecchi"),
        CheckBoxFilter("Fantasy", "Fantasy"),
        CheckBoxFilter("Gioco", "Gioco"),
        CheckBoxFilter("Harem", "Harem"),
        CheckBoxFilter("Hentai", "Hentai"),
        CheckBoxFilter("Horror", "Horror"),
        CheckBoxFilter("Josei", "Josei"),
        CheckBoxFilter("Magia", "Magia"),
        CheckBoxFilter("Mecha", "Mecha"),
        CheckBoxFilter("Militari", "Militari"),
        CheckBoxFilter("Mistero", "Mistero"),
        CheckBoxFilter("Musicale", "Musicale"),
        CheckBoxFilter("Parodia", "Parodia"),
        CheckBoxFilter("Polizia", "Polizia"),
        CheckBoxFilter("Psicologico", "Psicologico"),
        CheckBoxFilter("Romantico", "Romantico"),
        CheckBoxFilter("Samurai", "Samurai"),
        CheckBoxFilter("Sci-Fi", "Sci-Fi"),
        CheckBoxFilter("Scolastico", "Scolastico"),
        CheckBoxFilter("Seinen", "Seinen"),
        CheckBoxFilter("Sentimentale", "Sentimentale"),
        CheckBoxFilter("Shoujo Ai", "Shoujo Ai"),
        CheckBoxFilter("Shoujo", "Shoujo"),
        CheckBoxFilter("Shounen Ai", "Shounen Ai"),
        CheckBoxFilter("Shounen", "Shounen"),
        CheckBoxFilter("Slice of Life", "Slice of Life"),
        CheckBoxFilter("Soprannaturale", "Soprannaturale"),
        CheckBoxFilter("Spazio", "Spazio"),
        CheckBoxFilter("Sport", "Sport"),
        CheckBoxFilter("Storico", "Storico"),
        CheckBoxFilter("Superpoteri", "Superpoteri"),
        CheckBoxFilter("Thriller", "Thriller"),
        CheckBoxFilter("Vampiri", "Vampiri"),
        CheckBoxFilter("Veicoli", "Veicoli"),
        CheckBoxFilter("Yaoi", "Yaoi"),
        CheckBoxFilter("Yuri", "Yuri"),
      ]),
      GroupFilter("YearList", "Anno di Uscita", [
        for (var i = 1969; i < 2026; i++)
          CheckBoxFilter(i.toString(), i.toString()),
      ]),
      GroupFilter("StateList", "Stato", [
        CheckBoxFilter("In corso", "0"),
        CheckBoxFilter("Finito", "1"),
        CheckBoxFilter("Non rilasciato", "2"),
        CheckBoxFilter("Droppato", "3"),
      ]),
      SelectFilter("LangList", "Lingua", 0, [
        SelectFilterOption("", ""),
        SelectFilterOption("Subbato", "0"),
        SelectFilterOption("Doppiato", "1"),
      ]),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      ListPreference(
        key: "preferred_quality",
        title: "Qualità preferita",
        summary: "",
        valueIndex: 0,
        entries: ["1080p", "720p", "480p", "360p", "240p", "144p"],
        entryValues: ["1080", "720", "480", "360", "240", "144"],
      ),
    ];
  }

  List<MVideo> sortVideos(List<MVideo> videos, int sourceId) {
    String quality = getPreferenceValue(sourceId, "preferred_quality");

    videos.sort((MVideo a, B) {
      int qualityMatchA = a.quality.contains(quality) ? 1 : 0;
      int qualityMatchB = b.quality.contains(quality) ? 1 : 0;
      if (qualityMatchA != qualityMatchB) {
        return qualityMatchB - qualityMatchA;
      }

      final regex = RegExp(r'(\d+)p');
      final matchA = regex.firstMatch(a.quality);
      final matchB = regex.firstMatch(b.quality);
      final int qualityNumA = int.tryParse(matchA?.group(1) ?? '0') ?? 0;
      final int qualityNumB = int.tryParse(matchB?.group(1) ?? '0') ?? 0;
      return qualityNumB - qualityNumA;
    });

    return videos;
  }
}

AnimeSaturn main(MSource source) {
  return AnimeSaturn(source: source);
}
