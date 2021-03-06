import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pixiv/main.dart';
import 'package:pixiv/model/account.dart';
import 'package:pixiv/model/error_message.dart';
import 'package:pixiv/net/api_client.dart';
import 'package:pixiv/net/oauth_client.dart';

class RefreshTokenInterceptor extends Interceptor {
  Future<String> getToken() async {
    String token = accountStore?.now?.accessToken; //可能读的时候没有错的快，导致now为null
    String result;
    if (token != null)
      result = "Bearer " + token;
    else {
      AccountProvider accountProvider = AccountProvider();
      await accountProvider.open();
      final all = await accountProvider.getAllAccount();
      result = "Bearer " + all[accountStore.index].accessToken;
    }
    return result;
  }

  @override
  Future onRequest(RequestOptions options) async {
    if (options.path.contains('v1/walkthrough/illusts')) return options;
    options.headers[OAuthClient.AUTHORIZATION] = await getToken();
    return options; //continue
  }

  int bti(bool bool) {
    if (bool) {
      return 1;
    } else
      return 0;
  }

  int lastRefreshTime = 0;
  int retryNum = 0;

  @override
  Future onResponse(Response response) {
    retryNum = 0;
    return super.onResponse(response);
  }

  bool isRefreshing = false;

  @override
  onError(DioError err) async {
    if (err.response != null && err.response.statusCode == 400) {
      DateTime dateTime = DateTime.now();
      if ((dateTime.millisecondsSinceEpoch - lastRefreshTime) > 200000) {
        apiClient.httpClient.interceptors.errorLock.lock();
        print("refresh token start ========================");
        try {
          ErrorMessage errorMessage = ErrorMessage.fromJson(err.response.data);
          if (errorMessage.error.message.contains("OAuth") && accountStore.now != null) {
            final client = OAuthClient();
            AccountPersist accountPersist = accountStore.now;
            Response response1 =
                await client.postRefreshAuthToken(refreshToken: accountPersist.refreshToken, deviceToken: accountPersist.deviceToken);
            AccountResponse accountResponse = Account.fromJson(response1.data).response;
            final user = accountResponse.user;
            accountStore.updateSingle(AccountPersist()
              ..id = accountPersist.id
              ..accessToken = accountResponse.accessToken
              ..deviceToken = accountResponse.deviceToken
              ..refreshToken = accountResponse.refreshToken
              ..userImage = user.profileImageUrls.px170x170
              ..userId = user.id
              ..name = user.name
              ..passWord = accountPersist.passWord
              ..isMailAuthorized = bti(user.isMailAuthorized)
              ..isPremium = bti(user.isPremium)
              ..mailAddress = user.mailAddress
              ..account = user.account
              ..xRestrict = user.xRestrict);
            lastRefreshTime = DateTime.now().millisecondsSinceEpoch;
          }
          if (errorMessage.error.message.contains("Limit")) {}
        } catch (e) {
          print(e);
          lastRefreshTime = 0;
          return e;
        }
        print("refresh unlock ========================");
        apiClient.httpClient.interceptors.errorLock.unlock();
      }
      var request = err.response.request;
      request.headers[OAuthClient.AUTHORIZATION] = (await getToken());
      var response = await apiClient.httpClient.request(
        request.path,
        data: request.data,
        queryParameters: request.queryParameters,
        cancelToken: request.cancelToken,
        options: request,
      );
      return response;
    }
    if (err.message != null && err.message.contains("Connection closed before full header was received") && retryNum < 2) {
      print('retry $retryNum =========================');
      retryNum++;
      RequestOptions options = err.request;
      return apiClient.httpClient.request(
        options.path,
        options: options,
        data: options.data,
        queryParameters: options.queryParameters,
      );
    }
    super.onError(err);
  }
}
