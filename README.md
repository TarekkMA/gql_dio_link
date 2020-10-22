# :traffic_light: Moved to [`gql-dart/gql/links/gql_dio_link`](https://github.com/gql-dart/gql/blob/master/links/gql_dio_link/README.md).
## :tada:	 gql_dio_link is now part of the gql family.
## :information_source: Please go to [`gql-dart/gql`](https://github.com/gql-dart/gql) for more info.

Similar to [`gql_http_link`](https://pub.dev/packages/gql_http_link), This is a GQL Terminating Link to execute requests via Dio using JSON.

## Usage

A simple usage example:

```dart
import "package:dio/dio.dart";
import "package:gql_link/gql_link.dart";
import "package:gql_dio_link/gql_dio_link.dart";

void main () {
  final dio = Dio();
  final link = Link.from([
    // SomeLink(),
    DioLink("/graphql", client: dio),
  ]);
}

```

## Features and bugs

Please file feature requests and bugs at the [GitHub][tracker].

[tracker]: https://github.com/TarekkMA/gql_dio_link/issues

## Attribution
This code is adapted from [gql_http_link](https://github.com/gql-dart/gql/blob/master/links/gql_http_link/README.md).
