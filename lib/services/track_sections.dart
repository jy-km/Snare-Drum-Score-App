import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/rhythm_score.dart';

/// A stretch of a track (its "mother" track) saved for practising on its
/// own -- e.g. the fill in measures 5-8. It holds no notes of its own: it
/// points at a range of the mother track's measures, so editing the mother
/// track changes the section too.
@immutable
class TrackSection {
  final String id;

  /// The mother track (its score file name).
  final String trackId;
  final String name;

  /// The range, as 0-based measure indexes into the mother track, both ends
  /// included.
  final int firstMeasure;
  final int lastMeasure;

  const TrackSection({
    required this.id,
    required this.trackId,
    required this.name,
    required this.firstMeasure,
    required this.lastMeasure,
  }) : assert(firstMeasure <= lastMeasure);

  /// "m. 5-8" (or "m. 5" for one measure), numbered from 1 as players do.
  String get rangeLabel => firstMeasure == lastMeasure
      ? 'm. ${firstMeasure + 1}'
      : 'm. ${firstMeasure + 1}–${lastMeasure + 1}';

  /// The section's measures of [mother], as a score of their own to
  /// practise -- with the mother track's tempo and instrument -- or null if
  /// the mother track no longer reaches this far.
  RhythmScore? extractFrom(RhythmScore mother) {
    if (lastMeasure >= mother.measures.length) return null;
    return mother.copyWith(
      title: '${mother.title} · $name',
      measures: mother.measures.sublist(firstMeasure, lastMeasure + 1),
    );
  }

  TrackSection copyWith({String? name, int? firstMeasure, int? lastMeasure}) => TrackSection(
        id: id,
        trackId: trackId,
        name: name ?? this.name,
        firstMeasure: firstMeasure ?? this.firstMeasure,
        lastMeasure: lastMeasure ?? this.lastMeasure,
      );

  /// This section after measure [deleted] of the mother track is deleted:
  /// later measures move up one, so the range follows them; a range that
  /// contained the deleted measure loses it. Null if nothing is left.
  TrackSection? afterMeasureDeleted(int deleted) {
    if (deleted > lastMeasure) return this;
    if (deleted < firstMeasure) {
      return copyWith(firstMeasure: firstMeasure - 1, lastMeasure: lastMeasure - 1);
    }
    if (firstMeasure == lastMeasure) return null;
    return copyWith(lastMeasure: lastMeasure - 1);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'trackId': trackId,
        'name': name,
        'firstMeasure': firstMeasure,
        'lastMeasure': lastMeasure,
      };

  static TrackSection fromJson(Map<String, dynamic> json) => TrackSection(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        firstMeasure: json['firstMeasure'] as int,
        lastMeasure: json['lastMeasure'] as int,
      );
}

/// Keeps every track's sections.
abstract class SectionStore {
  /// All sections, of every track.
  Future<List<TrackSection>> load();
  Future<void> save(List<TrackSection> sections);
}

/// Stores the sections as one small JSON file in the app's documents
/// directory.
class FileSectionStore implements SectionStore {
  final Future<Directory> Function() _root;

  FileSectionStore({Future<Directory> Function()? root})
      : _root = root ?? getApplicationDocumentsDirectory;

  Future<File> _file() async => File('${(await _root()).path}/sections.json');

  @override
  Future<List<TrackSection>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    return [
      for (final entry in jsonDecode(await file.readAsString()) as List)
        TrackSection.fromJson(entry as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> save(List<TrackSection> sections) async {
    final file = await _file();
    await file.writeAsString(jsonEncode([for (final section in sections) section.toJson()]));
  }
}

/// Changes to a track's sections, in one place for every screen that makes
/// them.
class TrackSections {
  final SectionStore store;

  TrackSections(this.store);

  /// [trackId]'s sections, in the order they come in the track.
  Future<List<TrackSection>> forTrack(String trackId) async {
    final sections = [
      for (final section in await store.load())
        if (section.trackId == trackId) section,
    ]..sort((a, b) {
        final byStart = a.firstMeasure.compareTo(b.firstMeasure);
        return byStart != 0 ? byStart : a.lastMeasure.compareTo(b.lastMeasure);
      });
    return sections;
  }

  /// Saves a new section, or the changes to an existing one (same id).
  Future<void> put(TrackSection section) async {
    final all = await store.load();
    await store.save([
      for (final other in all)
        if (other.id != section.id) other,
      section,
    ]);
  }

  Future<void> delete(TrackSection section) async {
    final all = await store.load();
    await store.save([for (final other in all) if (other.id != section.id) other]);
  }

  /// Removes every section of a track (when the track itself is deleted).
  Future<void> deleteAllFor(String trackId) async {
    final all = await store.load();
    await store.save([for (final other in all) if (other.trackId != trackId) other]);
  }

  /// Keeps [trackId]'s sections on the same music after its measure
  /// [deleted] is deleted (see [TrackSection.afterMeasureDeleted]).
  Future<void> measureDeleted(String trackId, int deleted) async {
    final all = await store.load();
    await store.save([
      for (final section in all)
        if (section.trackId != trackId) section else ?section.afterMeasureDeleted(deleted),
    ]);
  }
}
