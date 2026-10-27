import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/rhythm_score.dart';
import 'hit_judge.dart';
import 'midi_score_codec.dart';
import 'run_review.dart';
import 'timeline_layout.dart';
import 'track_sections.dart';

/// How well a run went, as one number from 0 to 1 -- or null if there was
/// nothing to judge. Each note earns Perfect 100%, Great 75%, Good 50% or
/// Miss 0%, averaged over the notes; each Fail (a hit during a rest) counts
/// as one more note missed.
double? runAccuracy(Map<Judgement, int> counts) {
  int count(Judgement judgement) => counts[judgement] ?? 0;
  final judged =
      count(Judgement.perfect) +
      count(Judgement.great) +
      count(Judgement.good) +
      count(Judgement.miss) +
      count(Judgement.fail);
  if (judged == 0) return null;
  final credit =
      count(Judgement.perfect) * 1.0 + count(Judgement.great) * 0.75 + count(Judgement.good) * 0.5;
  return credit / judged;
}

/// "87%".
String accuracyText(double accuracy) => '${(accuracy * 100).round()}%';

/// One saved practice run, as listed in its track's history -- everything
/// but the recording and the per-note detail, which [PracticeHistoryStore.
/// loadReview] reads when the run is opened.
class PracticeRun {
  /// Unique within its track: when the run was saved, in ms since 1970.
  final String id;

  /// The track (score file) the run was of.
  final String scoreId;

  final DateTime startedAt;
  final int tempoBpm;

  /// The note [tempoBpm] counted when the run was played.
  final TempoBeat tempoBeat;

  final Map<Judgement, int> counts;

  /// How long the recording is.
  final double durationSeconds;

  /// What the player wrote about the run, if anything.
  final String note;

  final bool timingEstimated;

  /// For a run of a section rather than the whole track: the section's name
  /// and range as they were when played. Null for a whole-track run.
  final RunSection? section;

  const PracticeRun({
    required this.id,
    required this.scoreId,
    required this.startedAt,
    required this.tempoBpm,
    this.tempoBeat = TempoBeat.quarter,
    required this.counts,
    required this.durationSeconds,
    required this.note,
    required this.timingEstimated,
    this.section,
  });

  double? get accuracy => runAccuracy(counts);

  PracticeRun withNote(String note) => PracticeRun(
    id: id,
    scoreId: scoreId,
    startedAt: startedAt,
    tempoBpm: tempoBpm,
    tempoBeat: tempoBeat,
    counts: counts,
    durationSeconds: durationSeconds,
    note: note,
    timingEstimated: timingEstimated,
    section: section,
  );
}

/// Which section of its track a run was of.
@immutable
class RunSection {
  final String name;

  /// 0-based measure indexes into the track, both included.
  final int firstMeasure;
  final int lastMeasure;

  const RunSection({required this.name, required this.firstMeasure, required this.lastMeasure});

  factory RunSection.of(TrackSection section) => RunSection(
    name: section.name,
    firstMeasure: section.firstMeasure,
    lastMeasure: section.lastMeasure,
  );

  /// "Fill (m. 5–8)".
  String get label => firstMeasure == lastMeasure
      ? '$name (m. ${firstMeasure + 1})'
      : '$name (m. ${firstMeasure + 1}–${lastMeasure + 1})';

  Map<String, Object?> toJson() => {
    'name': name,
    'firstMeasure': firstMeasure,
    'lastMeasure': lastMeasure,
  };

  static RunSection fromJson(Map<String, dynamic> json) => RunSection(
    name: json['name'] as String,
    firstMeasure: json['firstMeasure'] as int,
    lastMeasure: json['lastMeasure'] as int,
  );
}

/// Keeps every judged practice run -- its recording, its judgements and
/// the score as it was at the time (so a run still reviews correctly after
/// the score is edited) -- grouped by track.
abstract class PracticeHistoryStore {
  /// Saves a finished run and returns how it is listed. [section] is set
  /// for a run of a section of the track.
  Future<PracticeRun> save({
    required String scoreId,
    required RunReview review,
    required int tempoBpm,
    required DateTime startedAt,
    RunSection? section,
  });

  /// A track's runs, newest first.
  Future<List<PracticeRun>> runsFor(String scoreId);

  /// Everything needed to go over [run] again on the review screen.
  Future<RunReview> loadReview(PracticeRun run);

  Future<void> updateNote(PracticeRun run, String note);

  Future<void> delete(PracticeRun run);

  /// Removes every run of a track (e.g. when the track itself is deleted).
  Future<void> deleteAllFor(String scoreId);
}

/// Stores each run as two files in the app's documents directory, under
/// `history/<track>/`: `<run id>.json` (everything but the audio) and
/// `<run id>.pcm` (the recording, raw 16-bit mono -- about 5 MB a minute).
class FilePracticeHistoryStore implements PracticeHistoryStore {
  final Future<Directory> Function() _root;

  /// [root] is where the `history` folder goes; by default the app's
  /// documents directory. Replaceable for tests.
  FilePracticeHistoryStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationDocumentsDirectory;

  Future<Directory> _trackDir(String scoreId) async {
    final root = await _root();
    return Directory('${root.path}/history/$scoreId');
  }

  @override
  Future<PracticeRun> save({
    required String scoreId,
    required RunReview review,
    required int tempoBpm,
    required DateTime startedAt,
    RunSection? section,
  }) async {
    final dir = await _trackDir(scoreId);
    await dir.create(recursive: true);
    final run = PracticeRun(
      id: '${startedAt.millisecondsSinceEpoch}',
      scoreId: scoreId,
      startedAt: startedAt,
      tempoBpm: tempoBpm,
      tempoBeat: review.layout.score.tempoBeat,
      counts: review.counts,
      durationSeconds: review.audioSeconds,
      note: '',
      timingEstimated: review.timingEstimated,
      section: section,
    );
    await File('${dir.path}/${run.id}.pcm').writeAsBytes(
      review.audio.buffer.asUint8List(review.audio.offsetInBytes, review.audio.lengthInBytes),
    );
    await _writeJson(dir, run, review);
    return run;
  }

  Future<void> _writeJson(Directory dir, PracticeRun run, RunReview review) =>
      File('${dir.path}/${run.id}.json').writeAsString(jsonEncode(encodeRun(run, review)));

  @override
  Future<List<PracticeRun>> runsFor(String scoreId) async {
    final dir = await _trackDir(scoreId);
    if (!await dir.exists()) return const [];
    final runs = <PracticeRun>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
      runs.add(decodeRunSummary(json));
    }
    runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return runs;
  }

  @override
  Future<RunReview> loadReview(PracticeRun run) async {
    final dir = await _trackDir(run.scoreId);
    final json =
        jsonDecode(await File('${dir.path}/${run.id}.json').readAsString()) as Map<String, dynamic>;
    final bytes = await File('${dir.path}/${run.id}.pcm').readAsBytes();
    final audio = Int16List.view(Uint8List.fromList(bytes).buffer, 0, bytes.length ~/ 2);
    return decodeReview(json, audio);
  }

  @override
  Future<void> updateNote(PracticeRun run, String note) async {
    final dir = await _trackDir(run.scoreId);
    final file = File('${dir.path}/${run.id}.json');
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    json['note'] = note;
    await file.writeAsString(jsonEncode(json));
  }

  @override
  Future<void> delete(PracticeRun run) async {
    final dir = await _trackDir(run.scoreId);
    for (final extension in const ['json', 'pcm']) {
      final file = File('${dir.path}/${run.id}.$extension');
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> deleteAllFor(String scoreId) async {
    final dir = await _trackDir(scoreId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// The JSON a run is kept as. Shared with in-memory stores (tests) so they
// exercise the same encoding.

Map<String, Object?> encodeRun(PracticeRun run, RunReview review) => {
  'id': run.id,
  'scoreId': run.scoreId,
  'startedAt': run.startedAt.millisecondsSinceEpoch,
  'tempoBpm': run.tempoBpm,
  'tempoBeat': run.tempoBeat.name,
  'counts': {for (final entry in run.counts.entries) entry.key.name: entry.value},
  'durationSeconds': run.durationSeconds,
  'note': run.note,
  'timingEstimated': run.timingEstimated,
  if (run.section != null) 'section': run.section!.toJson(),
  // The score as it was when played, so the review still lines up after
  // the score is edited.
  'score': base64Encode(MidiScoreCodec.encode(review.layout.score)),
  'secondsPerUnit': review.secondsPerUnit,
  'noteTimes': review.noteTimes,
  'sampleRate': review.sampleRate,
  'judgements': [
    for (final hit in review.judgements)
      {
        'judgement': hit.judgement.name,
        'noteIndex': hit.noteIndex,
        'offsetSeconds': hit.offsetSeconds,
        'hitTimeSeconds': hit.hitTimeSeconds,
      },
  ],
};

PracticeRun decodeRunSummary(Map<String, dynamic> json) => PracticeRun(
  id: json['id'] as String,
  scoreId: json['scoreId'] as String,
  startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
  tempoBpm: json['tempoBpm'] as int,
  // Runs saved before the beat could be chosen counted quarter notes.
  tempoBeat: TempoBeat.values.asNameMap()[json['tempoBeat']] ?? TempoBeat.quarter,
  counts: {
    for (final entry in (json['counts'] as Map<String, dynamic>).entries)
      Judgement.values.byName(entry.key): entry.value as int,
  },
  durationSeconds: (json['durationSeconds'] as num).toDouble(),
  note: json['note'] as String? ?? '',
  timingEstimated: json['timingEstimated'] as bool? ?? false,
  section: json['section'] == null
      ? null
      : RunSection.fromJson(json['section'] as Map<String, dynamic>),
);

RunReview decodeReview(Map<String, dynamic> json, Int16List audio) {
  final RhythmScore score = MidiScoreCodec.decode(base64Decode(json['score'] as String));
  return RunReview(
    // A section's measures are numbered as in its track.
    layout: TimelineLayout(
      score,
      firstMeasureNumber: (decodeRunSummary(json).section?.firstMeasure ?? 0) + 1,
    ),
    secondsPerUnit: (json['secondsPerUnit'] as num).toDouble(),
    noteTimes: [for (final time in json['noteTimes'] as List) (time as num).toDouble()],
    judgements: [
      for (final hit in json['judgements'] as List)
        JudgedHit(
          Judgement.values.byName((hit as Map<String, dynamic>)['judgement'] as String),
          noteIndex: hit['noteIndex'] as int?,
          offsetSeconds: (hit['offsetSeconds'] as num?)?.toDouble(),
          hitTimeSeconds: (hit['hitTimeSeconds'] as num?)?.toDouble(),
        ),
    ],
    counts: decodeRunSummary(json).counts,
    audio: audio,
    sampleRate: json['sampleRate'] as int,
    timingEstimated: json['timingEstimated'] as bool? ?? false,
  );
}
