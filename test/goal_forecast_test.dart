import 'dart:convert';
import 'dart:io';

import 'package:budget_app/capture/capture_service.dart';
import 'package:budget_app/data/database.dart';
import 'package:budget_app/data/rates.dart';
import 'package:budget_app/data/repository.dart';
import 'package:budget_app/domain/runway.dart';
import 'package:budget_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Goals and the forecast's planned spending are one kind of plan: a goal with a deadline is the
/// purchase on that day, and a planned purchase can become a goal.
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState state;
  final now = DateTime.now();
  final inTwoMonths = DateTime(now.year, now.month + 2, 15);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('budget_goalrun_');
    final db = await openAppDatabase(factory: databaseFactoryFfi, path: '${tmp.path}/b.db');
    state = AppState(Repository(db), CaptureService(),
        RatesService(db, client: MockClient((_) async => http.Response(jsonEncode({'date': '2026-10-18', 'cny': {}}), 200))));
    await state.init();
  });
  tearDown(() async {
    await state.repo.db.close();
    tmp.deleteSync(recursive: true);
  });

  test('a goal with a deadline is the purchase on that day; reached or undated goals are not', () async {
    await state.addGoal(name: 'Ноутбук', targetMinor: 500000, savedMinor: 100000, deadline: inTwoMonths, reserve: true);
    await state.addGoal(name: 'Подушка', targetMinor: 900000, savedMinor: 0, reserve: true);
    await state.addGoal(name: 'Билеты', targetMinor: 50000, savedMinor: 50000, deadline: inTwoMonths, reserve: true);

    // Savings not counted as available money: only the part still to save leaves on the day.
    final notCounted = state.goalsPlanned(const RunwayConfig());
    expect(notCounted, hasLength(1));
    expect(notCounted.single.name, 'Ноутбук');
    expect(notCounted.single.amountMinor, -400000);
    expect(notCounted.single.date, inTwoMonths);

    // Savings counted as available: the whole price leaves on the day.
    expect(state.goalsPlanned(const RunwayConfig(includeGoalSavings: true)).single.amountMinor, -500000);
  });

  test('the forecast counts goal purchases unless switched off, and the switch is kept', () async {
    await state.addGoal(name: 'Ноутбук', targetMinor: 500000, savedMinor: 0, deadline: inTwoMonths, reserve: true);
    final on = await state.computeRunwayFor(const RunwayConfig(useRecurring: false));
    final off = await state.computeRunwayFor(const RunwayConfig(useRecurring: false, useGoals: false));
    expect(on.projection.last.balanceMinor, lessThan(off.projection.last.balanceMinor));
    final back = RunwayConfig.fromJsonString(const RunwayConfig(useGoals: false).toJsonString());
    expect(back.useGoals, isFalse);
    expect(RunwayConfig.fromJsonString('{}').useGoals, isTrue, reason: 'on by default, also for old settings');
  });

  test('a planned purchase becomes a goal and leaves the planned list', () async {
    final p = PlannedItem(name: 'Отпуск', amountMinor: -300000, date: inTwoMonths);
    await state.saveRunwayConfig(state.runwayConfig.copyWith(planned: [p]));
    await state.saveForPlanned(state.runwayConfig.planned.single);
    expect(state.runwayConfig.planned, isEmpty);
    final g = state.goals.singleWhere((g) => g.name == 'Отпуск');
    expect(g.targetMinor, 300000);
    expect(g.deadline, inTwoMonths);
    // And it is in the forecast now, as a goal.
    expect(state.goalsPlanned(state.runwayConfig).single.name, 'Отпуск');
  });
}
