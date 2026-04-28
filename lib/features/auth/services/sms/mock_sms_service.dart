import 'i_sms_service.dart';
import 'package:flutter/foundation.dart';

class MockSmsService implements ISmsService {
  @override
  Future<void> sendOtp(String phone, String otp) async {
    debugPrint('[MockSMS] OTP for $phone is $otp');
  }
}
