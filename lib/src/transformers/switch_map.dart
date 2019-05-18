import 'dart:async';

/// Converts each emitted item into a new Stream using the given mapper
/// function. The newly created Stream will be be listened to and begin
/// emitting items, and any previously created Stream will stop emitting.
///
/// The switchMap operator is similar to the flatMap and concatMap
/// methods, but it only emits items from the most recently created Stream.
///
/// This can be useful when you only want the very latest state from
/// asynchronous APIs, for example.
///
/// ### Example
///
///     new Stream.fromIterable([4, 3, 2, 1])
///       .transform(new SwitchMapStreamTransformer((i) =>
///         new Stream.fromFuture(
///           new Future.delayed(new Duration(minutes: i), () => i))
///       .listen(print); // prints 1
class SwitchMapStreamTransformer<T, S> extends StreamTransformerBase<T, S> {
  final StreamTransformer<T, S> transformer;

  SwitchMapStreamTransformer(Stream<S> mapper(T value))
      : transformer = _buildTransformer(mapper);

  @override
  Stream<S> bind(Stream<T> stream) => transformer.bind(stream);

  static StreamTransformer<T, S> _buildTransformer<T, S>(
      Stream<S> mapper(T value)) {
    return StreamTransformer<T, S>((Stream<T> input, bool cancelOnError) {
      StreamController<S> controller;
      StreamSubscription<T> leftSubscription;
      StreamSubscription<S> rightSubscription;
      var leftClosed = false, rightClosed = false, hasMainEvent = false;

      controller = StreamController<S>(
          sync: true,
          onListen: () {
            leftSubscription = input.listen(
                (T value) {
                  try {
                    rightSubscription?.cancel();

                    hasMainEvent = true;

                    rightSubscription = mapper(value).listen(controller.add,
                        onError: controller.addError, onDone: () {
                      rightClosed = true;

                      if (leftClosed) controller.close();
                    });
                  } catch (e, s) {
                    controller.addError(e, s);
                  }
                },
                onError: controller.addError,
                onDone: () {
                  leftClosed = true;

                  if (rightClosed && !hasMainEvent) controller.close();
                },
                cancelOnError: cancelOnError);
          },
          onPause: ([Future<dynamic> resumeSignal]) {
            leftSubscription.pause(resumeSignal);
            rightSubscription?.pause(resumeSignal);
          },
          onResume: () {
            leftSubscription.resume();
            rightSubscription?.resume();
          },
          onCancel: () async {
            await leftSubscription.cancel();

            if (hasMainEvent) await rightSubscription.cancel();
          });

      return controller.stream.listen(null);
    });
  }
}
