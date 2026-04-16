import 'i_sms_service.dart';
import 'mock_sms_service.dart';

class SmsServiceLocator {
  static ISmsService sms = MockSmsService();
}

