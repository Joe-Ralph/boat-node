class BoatUtils {
  static String getDynamicBoatName(String? userName) {
    if (userName != null && userName.isNotEmpty) {
      // "Joe Ralphin" -> "Joe" -> "Joe's Boat"
      final firstName = userName.trim().split(' ').first;
      return "$firstName's Boat";
    }
    return "My Boat";
  }
}
