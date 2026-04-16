abstract class ISmsService {
  Future<void> sendOtp(String phone, String otp);
}

