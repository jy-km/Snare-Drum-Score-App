import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/live_judge.dart';
import 'package:snare_drum_score_app/services/onset_detector.dart';

import 'support/synth_audio.dart';

/// Feeds [recording] to [judge] the way a microphone would, in ~80ms chunks,
/// and collects everything it judged along the way.
List<JudgedHit> _feed(LiveJudge judge, Int16List recording) {
  const chunk = 3528;
  final judged = <JudgedHit>[];
  for (var start = 0; start < recording.length; start += chunk) {
    final end = start + chunk < recording.length ? start + chunk : recording.length;
    judged.addAll(judge.addSamples(Int16List.sublistView(recording, start, end)));
  }
  return judged;
}

void main() {
  // A 4-beat count-in at 120 BPM, then four quarter notes.
  const clickTimes = [0.0, 0.5, 1.0, 1.5];
  const noteTimes = [2.0, 2.5, 3.0, 3.5];

  /// How long the "microphone" was already running when the timeline began.
  const micLead = 0.37;

  // The judge is told the timeline starts 0.2s into the recording -- 0.17s
  // off, as a real estimate would be off by the phone's audio delays.
  LiveJudge newJudge() => LiveJudge(
        sampleRate: synthSampleRate,
        clickTimes: clickTimes,
        noteTimes: noteTimes,
        judgingStartsAt: 2.0,
      )..expectTimelineStart(0.2);

  Int16List recordingWith(List<double> timelineTimes, {double seconds = 5}) => synthRecording(
        seconds: seconds,
        hitTimes: [for (final time in timelineTimes) micLead + time],
      );

  test('Judges each hit against its note once the count-in has been heard', () {
    final judge = newJudge();
    expect(judge.state, LiveJudgeState.listeningForCountIn);

    final judged = _feed(
      judge,
      // On time, 60ms late, 100ms early, and the last note not played.
      recordingWith([...clickTimes, 2.0, 2.56, 2.9]),
    );
    judged.addAll(judge.finish());

    expect(judge.state, LiveJudgeState.judging);
    expect(judge.timingIsEstimated, isFalse);
    // The count-in pins the timeline's start down exactly, however rough
    // the estimate it was given.
    expect(judge.heardTimelineStart, closeTo(micLead, 0.008));
    expect(
      judged.map((j) => j.judgement),
      [Judgement.perfect, Judgement.great, Judgement.good, Judgement.miss],
    );
    expect(judged.map((j) => j.noteIndex), [0, 1, 2, 3]);
    // Where each hit landed on the timeline; none for the note not played.
    expect(judged[1].hitTimeSeconds, closeTo(2.56, 0.008));
    expect(judged[3].hitTimeSeconds, isNull);
    expect(judged[0].offsetSeconds, closeTo(0, 0.008));
    expect(judged[1].offsetSeconds, closeTo(0.06, 0.008));
    expect(judged[2].offsetSeconds, closeTo(-0.1, 0.008));
    expect(judge.counts[Judgement.miss], 1);
  });

  test('A missed note is reported while the run is still going, not only at the end', () {
    final judge = newJudge();

    // Only the first note is played; the recording runs on past the others.
    final judged = _feed(judge, recordingWith([...clickTimes, 2.0]));

    expect(
      judged.map((j) => j.judgement),
      [Judgement.perfect, Judgement.miss, Judgement.miss, Judgement.miss],
    );
  });

  test('Tapping along with the count-in is not judged', () {
    final judge = newJudge();

    final judged = _feed(judge, recordingWith([...clickTimes, 0.25, 0.75, 1.25, 2.0]));

    expect(judge.state, LiveJudgeState.judging);
    expect(judged.first.judgement, Judgement.perfect);
    expect(judged.first.noteIndex, 0);
    // One judgement per note: the taps add none of their own.
    expect(judged.map((j) => j.noteIndex), [0, 1, 2, 3]);
    expect(judged.skip(1).every((j) => j.judgement == Judgement.miss), isTrue);
  });

  test('Gives up, judging nothing, when the count-in is never heard', () {
    final judge = newJudge();

    // The player plays, but no clicks reach the microphone (headphones).
    // Their four evenly spaced notes look exactly like the count-in, one
    // measure late -- which must not be mistaken for it.
    final judged = _feed(judge, recordingWith([2.0, 2.5, 3.0, 3.5], seconds: 6));

    expect(judge.state, LiveJudgeState.countInNotHeard);
    expect(judged, isEmpty);
    expect(judge.finish(), isEmpty);
  });

  test('With a trusted estimate, a run whose count-in is never heard is judged by the estimate',
      () {
    final judge = LiveJudge(
      sampleRate: synthSampleRate,
      clickTimes: clickTimes,
      noteTimes: noteTimes,
      judgingStartsAt: 2.0,
    )..expectTimelineStart(micLead + 0.02, trusted: true);

    // No clicks reach the microphone; the player plays every note on time.
    final judged = _feed(judge, recordingWith(noteTimes, seconds: 6));

    expect(judge.state, LiveJudgeState.judging);
    expect(judge.timingIsEstimated, isTrue);
    expect(judge.heardTimelineStart, isNull);
    expect(judged.map((j) => j.noteIndex), [0, 1, 2, 3]);
    // Judged against the estimate, so the estimate's 20ms error shows up in
    // every hit.
    for (final hit in judged) {
      expect(hit.judgement, Judgement.perfect);
      expect(hit.offsetSeconds, closeTo(-0.02, 0.008));
    }
  });

  test('A trusted estimate is not used when the count-in is heard', () {
    final judge = LiveJudge(
      sampleRate: synthSampleRate,
      clickTimes: clickTimes,
      noteTimes: noteTimes,
      judgingStartsAt: 2.0,
    )..expectTimelineStart(micLead + 0.1, trusted: true);

    final judged = _feed(judge, recordingWith([...clickTimes, ...noteTimes]));

    expect(judge.timingIsEstimated, isFalse);
    expect(judged.first.offsetSeconds, closeTo(0, 0.008));
  });

  test('Judges nothing until it has been told when the timeline started', () {
    final judge = LiveJudge(
      sampleRate: synthSampleRate,
      clickTimes: clickTimes,
      noteTimes: noteTimes,
      judgingStartsAt: 2.0,
    );
    final recording = recordingWith([...clickTimes, 2.0, 2.5]);
    final half = recording.length ~/ 2;

    expect(_feed(judge, Int16List.sublistView(recording, 0, half)), isEmpty);
    expect(judge.state, LiveJudgeState.listeningForCountIn);

    // Told late, 2.5s into the recording.
    judge.expectTimelineStart(0.3);
    final judged = _feed(judge, Int16List.sublistView(recording, half));

    expect(judge.state, LiveJudgeState.judging);
    expect(judged.take(2).map((j) => j.judgement), [Judgement.perfect, Judgement.perfect]);
  });

  group('alignCountIn', () {
    test('finds the count-in among stray sounds before it', () {
      final offset = LiveJudge.alignCountIn(
        [0.1, 0.42, 0.92, 1.43, 1.92],
        clickTimes,
        0.03,
      );
      // Clicks heard at 0.42, 0.92, 1.43, 1.92: timeline zero is ~0.4225.
      expect(offset, closeTo(0.4225, 1e-9));
    });

    test('returns null until every click has been heard', () {
      expect(LiveJudge.alignCountIn([0.42, 0.92, 1.42], clickTimes, 0.03), isNull);
      expect(LiveJudge.alignCountIn(const [], clickTimes, 0.03), isNull);
    });

    test('returns null when the sounds are not spaced like the count-in', () {
      expect(LiveJudge.alignCountIn([0.4, 0.8, 1.2, 1.6], clickTimes, 0.03), isNull);
    });
  });

  test('The streaming detector finds the same hits as the whole-recording one', () {
    final hitTimes = [0.4, 0.9, 1.0, 1.1, 1.2, 2.0, 2.75];
    final recording = synthRecording(seconds: 3.5, hitTimes: hitTimes);

    final streaming = StreamingOnsetDetector(sampleRate: synthSampleRate);
    final streamed = <Onset>[];
    const chunk = 1000; // deliberately not a multiple of the analysis hop
    for (var start = 0; start < recording.length; start += chunk) {
      final end = start + chunk < recording.length ? start + chunk : recording.length;
      streamed.addAll(streaming.addSamples(Int16List.sublistView(recording, start, end)));
    }
    final whole = OnsetDetector.detect(recording, sampleRate: synthSampleRate);

    expect(streamed.length, hitTimes.length);
    expect(whole.length, hitTimes.length);
    for (var i = 0; i < hitTimes.length; i++) {
      expect(streamed[i].timeSeconds, closeTo(hitTimes[i], 0.008));
      expect(streamed[i].timeSeconds, whole[i].timeSeconds);
    }
    // Every hit is reported within the promised delay of its audio arriving.
    expect(streaming.latencySeconds, lessThan(0.08));
  });
}
