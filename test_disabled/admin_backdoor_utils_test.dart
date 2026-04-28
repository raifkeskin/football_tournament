import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/utils/admin_backdoor_utils.dart';

void main() {
  test('matchesBackdoorPassword checks multiple field names', () {
    expect(
      matchesBackdoorPassword({'password': '123'}, '123'),
      true,
    );
    expect(
      matchesBackdoorPassword({'backdoorPassword': 'abc'}, 'abc'),
      true,
    );
    expect(
      matchesBackdoorPassword({'sifre': 'x'}, 'x'),
      true,
    );
    expect(
      matchesBackdoorPassword({'secret': 'y'}, 'y'),
      true,
    );
    expect(
      matchesBackdoorPassword({'pin': '999999'}, '999999'),
      true,
    );
    expect(
      matchesBackdoorPassword({'password': '123'}, '124'),
      false,
    );
  });
}

