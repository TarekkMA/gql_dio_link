import 'dart:convert';
import "package:dio/dio.dart" as dio;
import "package:gql_exec/gql_exec.dart";
import "package:gql_link/gql_link.dart";
import "package:meta/meta.dart";

import "exceptions.dart";

/// HTTP link headers
@immutable
class HttpLinkHeaders extends ContextEntry {
  /// Headers to be added to the request.
  ///
  /// May overrides Apollo Client awareness headers.
  final Map<String, String> headers;

  const HttpLinkHeaders({
    this.headers = const {},
  }) : assert(headers != null);

  @override
  List<Object> get fieldsForEquality =>
      [
        headers,
      ];
}

/// Dio link Response Context
@immutable
class DioLinkResponseContext extends ContextEntry {
  /// Dio status code of the response
  final int statusCode;

  const DioLinkResponseContext({
    @required this.statusCode,
  }) : assert(statusCode != null);

  @override
  List<Object> get fieldsForEquality =>
      [
        statusCode,
      ];
}

extension _CastDioResponse on dio.Response {
  dio.Response<T> castData<T>() =>
      dio.Response<T>(
        data: data as T,
        headers: headers,
        request: request,
        isRedirect: isRedirect,
        statusCode: statusCode,
        statusMessage: statusMessage,
        redirects: redirects,
      );
}

/// A simple HttpLink implementation using Dio.
///
/// To use non-standard [Request] and [Response] shapes
/// you can override [serializeRequest], [parseResponse]
class DioLink extends Link {
  /// Endpoint of the GraphQL service
  final String endpoint;

  /// Default HTTP headers
  final Map<String, String> defaultHeaders;

  /// Serializer used to serialize request
  final RequestSerializer serializer;

  /// Parser used to parse response
  final ResponseParser parser;

  /// Dio client instance.
  final dio.Dio client;

  DioLink(this.endpoint, {
    @required this.client,
    this.defaultHeaders = const {},
    this.serializer = const RequestSerializer(),
    this.parser = const ResponseParser(),
  }) : assert(client != null);

  @override
  Stream<Response> request(Request request, [forward]) async* {
    final dio.RequestOptions dioRequest = _prepareRequest(request);
    final dio.Response<Map<String, dynamic>> dioResponse =
    await _excuteDioRequest(
      body: dioRequest.data,
      headers: dioRequest.headers,
    );

    if (dioResponse.statusCode >= 300 ||
        (dioResponse.data["data"] == null &&
            dioResponse.data["errors"] == null)) {
      throw DioLinkServerException(
        response: dioResponse,
        parsedResponse: _parseDioResponse(dioResponse),
      );
    }

    final gqlResponse = _parseDioResponse(dioResponse);
    yield Response(
      data: gqlResponse.data,
      errors: gqlResponse.errors,
      context: _updateResponseContext(gqlResponse, dioResponse),
    );
  }

  dio.RequestOptions _prepareRequest(Request request) {
    try {
      final headers = {
        "Accept": "*/*",
        ...defaultHeaders,
        ..._getHttpLinkHeaders(request),
      };

      final body = _encodeAttempter(
        request,
        serializer.serializeRequest,
      )(request);

      final fileMap = extractFlattenedFileMap(body);
      if (!fileMap.isNotEmpty) {
        headers["Content-type"] = "application/json";
        return dio.RequestOptions(
            data: _serializeRequest(request), headers: headers);
      }

      var formData = dio.FormData();
      var operations = json.encode(body, toEncodable: (dynamic object) {
        if (object is dio.MultipartFile) {
          return null;
        }
        return object.toJson();
      });

      formData.fields.add(MapEntry('operations', operations));

      final Map<String, List<String>> fileMapping = <String, List<String>>{};

      int i = 0;
      fileMap.forEach((key, value) {
        final String indexString = i.toString();
        fileMapping.addAll(<String, List<String>>{
          indexString: <String>[key],
        });
        formData.files.add(MapEntry(i.toString(), value));
        i++;
      });

      formData.fields.add(MapEntry('map', json.encode(fileMapping)));

      return dio.RequestOptions(data: formData, headers: headers);
    } catch (e) {
      throw RequestFormatException(
        originalException: e,
        request: request,
      );
    }
  }

  Context _updateResponseContext(Response response,
      dio.Response httpResponse,) {
    try {
      return response.context.withEntry(
        DioLinkResponseContext(
          statusCode: httpResponse.statusCode,
        ),
      );
    } catch (e) {
      throw ContextWriteException(
        originalException: e,
      );
    }
  }

  Future<dio.Response<Map<String, dynamic>>> _excuteDioRequest({
    @required dynamic body,
    @required Map<String, String> headers,
  }) async {
    try {
      final res = await client.post<dynamic>(
        endpoint,
        data: body,
        options: dio.Options(
          responseType: dio.ResponseType.json,
          contentType: "application/json",
          headers: headers,
        ),
      );
      if (res.data is Map<String, dynamic> == false) {
        throw DioLinkParserException(
          // ignore: prefer_adjacent_string_concatenation
            originalException: "Expected response data to be of type " +
                "'Map<String, dynamic>' but found ${res.data.runtimeType}",
            response: res);
      }
      return res.castData<Map<String, dynamic>>();
    } on dio.DioError catch (e) {
      switch (e.type) {
        case dio.DioErrorType.CONNECT_TIMEOUT:
        case dio.DioErrorType.RECEIVE_TIMEOUT:
        case dio.DioErrorType.SEND_TIMEOUT:
          throw DioLinkTimeoutException(
            type: e.type,
            originalException: e,
          );
        case dio.DioErrorType.CANCEL:
          throw DioLinkCanceledException(originalException: e);
        case dio.DioErrorType.RESPONSE:
          {
            final res = e.response;
            final parsedResponse = (res.data is Map<String, dynamic>)
                ? parser.parseResponse(res.data as Map<String, dynamic>)
                : null;
            throw DioLinkServerException(
                response: res, parsedResponse: parsedResponse);
          }
        case dio.DioErrorType.DEFAULT:
        default:
          throw DioLinkUnkownException(originalException: e);
      }
    } catch (e) {
      throw DioLinkUnkownException(originalException: e);
    }
  }

  Response _parseDioResponse(dio.Response<Map<String, dynamic>> dioResponse) {
    try {
      return parser.parseResponse(dioResponse.data);
    } catch (e) {
      throw DioLinkParserException(
        originalException: e,
        response: dioResponse,
      );
    }
  }

  Map<String, dynamic> _serializeRequest(Request request) {
    try {
      return serializer.serializeRequest(request);
    } catch (e) {
      throw RequestFormatException(
        originalException: e,
        request: request,
      );
    }
  }

  Map<String, String> _getHttpLinkHeaders(Request request) {
    try {
      final HttpLinkHeaders linkHeaders = request.context.entry();
      return {
        if (linkHeaders != null) ...linkHeaders.headers,
      };
    } catch (e) {
      throw ContextReadException(
        originalException: e,
      );
    }
  }

  /// Closes the underlining Dio client
  void close({bool force = false}) {
    client?.close(force: force);
  }
}

/// wrap an encoding transform in exception handling
T Function(V) _encodeAttempter<T, V>(Request request,
    T Function(V) encoder,) =>
        (V input) {
      try {
        return encoder(input);
      } catch (e) {
        throw RequestFormatException(
          originalException: e,
          request: request,
        );
      }
    };

Map<String, dio.MultipartFile> extractFlattenedFileMap(dynamic body, {
  Map<String, dio.MultipartFile> currentMap,
  List<String> currentPath = const <String>[],
}) {
  currentMap ??= <String, dio.MultipartFile>{};
  if (body is Map<String, dynamic>) {
    final Iterable<MapEntry<String, dynamic>> entries = body.entries;
    for (final MapEntry<String, dynamic> element in entries) {
      currentMap.addAll(extractFlattenedFileMap(
        element.value,
        currentMap: currentMap,
        currentPath: List<String>.from(currentPath)
          ..add(element.key),
      ));
    }
    return currentMap;
  }
  if (body is List<dynamic>) {
    for (int i = 0; i < body.length; i++) {
      currentMap.addAll(extractFlattenedFileMap(
        body[i],
        currentMap: currentMap,
        currentPath: List<String>.from(currentPath)
          ..add(i.toString()),
      ));
    }
    return currentMap;
  }

  if (body is dio.MultipartFile) {
    return currentMap
      ..addAll({
        currentPath.join("."): body,
      });
  }

  assert(
  body is String || body is num || body == null,
  "$body of type ${body.runtimeType} was found "
      "in in the request at path ${currentPath.join(".")}, "
      "but the only the types { Map, List, MultipartFile, String, num, null } "
      "are allowed",
  );

  return currentMap;
}
