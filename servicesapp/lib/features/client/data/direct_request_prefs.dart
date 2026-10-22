import 'package:shared_preferences/shared_preferences.dart';

/// "Não voltar a mostrar" da explicação do pedido direto (design A5). Fica
/// no dispositivo, por conta: noutra conta ou noutro telemóvel a
/// explicação volta a aparecer uma vez.
class DirectRequestPrefs {
  const DirectRequestPrefs();

  static String _key(String userId) => 'direct_request_info_hidden_$userId';

  Future<bool> isInfoHidden(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> hideInfo(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
