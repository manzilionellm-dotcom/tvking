# Flutter charge ce fichier pour le build release NOVATUBE.
# API partagées nécessaires au banc contre le véritable APK release optimisé.
# Règles précises générées par R8 TraceReferences 9.3.16, sans keep global.
# Sources : runner 1.6.2, monitor 1.7.2, core 1.6.1, ext-junit 1.2.1,
# storage 1.5.0, concurrent-futures-ktx 1.1.0, JUnit 4.13.2,
# Hamcrest 1.3 et les quatre classes de GalleryExporterInstrumentedTest.
# Cibles résolues de l'app : Kotlin 2.3.21, coroutines 1.9.0,
# concurrent-futures 1.1.0, lifecycle-common 2.7.0, tracing 1.2.0,
# Guava 33.3.1-android, Flutter embedding du SDK 3.47.7.
# Les façades ET les membres hérités utilisés par le test sont conservés ;
# le reste du programme reste réductible, optimisable et renommable.
-keep @interface androidx.annotation.ChecksSdkIntAtLeast {
  public int api();
  public int extension();
}
-keep @interface androidx.annotation.GuardedBy {
  public java.lang.String value();
}
-keep @interface androidx.annotation.NonNull {
}
-keep @interface androidx.annotation.Nullable {
}
-keep @interface androidx.annotation.RequiresApi {
  public int value();
}
-keep enum androidx.annotation.RestrictTo$Scope {
  androidx.annotation.RestrictTo$Scope LIBRARY;
  androidx.annotation.RestrictTo$Scope LIBRARY_GROUP;
}
-keep @interface androidx.annotation.RestrictTo {
  public androidx.annotation.RestrictTo$Scope[] value();
}
-keep @interface androidx.annotation.VisibleForTesting {
}
-keep class androidx.concurrent.futures.AbstractResolvableFuture {
  public void addListener(java.lang.Runnable, java.util.concurrent.Executor);
  public boolean cancel(boolean);
  public java.lang.Object get();
  public java.lang.Object get(long, java.util.concurrent.TimeUnit);
  static java.lang.Object getUninterruptibly(java.util.concurrent.Future);
  public boolean isCancelled();
  public boolean isDone();
}
-keep class androidx.concurrent.futures.CallbackToFutureAdapter$Completer {
  public boolean set(java.lang.Object);
  public boolean setException(java.lang.Throwable);
}
-keep interface androidx.concurrent.futures.CallbackToFutureAdapter$Resolver {
  public java.lang.Object attachCompleter(androidx.concurrent.futures.CallbackToFutureAdapter$Completer);
}
-keep class androidx.concurrent.futures.CallbackToFutureAdapter {
  public static com.google.common.util.concurrent.ListenableFuture getFuture(androidx.concurrent.futures.CallbackToFutureAdapter$Resolver);
}
-keep enum androidx.concurrent.futures.DirectExecutor {
  androidx.concurrent.futures.DirectExecutor INSTANCE;
}
-keep class androidx.concurrent.futures.ResolvableFuture {
  public static androidx.concurrent.futures.ResolvableFuture create();
  public boolean set(java.lang.Object);
  public boolean setException(java.lang.Throwable);
}
-keep enum androidx.lifecycle.Lifecycle$State {
  public static androidx.lifecycle.Lifecycle$State[] values();
  androidx.lifecycle.Lifecycle$State CREATED;
  androidx.lifecycle.Lifecycle$State DESTROYED;
  androidx.lifecycle.Lifecycle$State RESUMED;
  androidx.lifecycle.Lifecycle$State STARTED;
}
-keep class androidx.lifecycle.Lifecycle {
}
-keep class androidx.tracing.Trace {
  public static void beginSection(java.lang.String);
  public static void endSection();
  public static void forceEnableAppTracing();
}
-keep interface com.google.common.util.concurrent.ListenableFuture {
  public void addListener(java.lang.Runnable, java.util.concurrent.Executor);
}
-keep @interface com.google.errorprone.annotations.CanIgnoreReturnValue {
}
-keep @interface com.google.errorprone.annotations.InlineMe {
  public java.lang.String replacement();
}
-keep @interface com.google.errorprone.annotations.MustBeClosed {
}
-keep class com.sevenmotion.novatube.GalleryExporter {
  public <init>(io.flutter.plugin.common.BinaryMessenger, android.content.Context, android.app.Activity);
  public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
}
-keep interface io.flutter.plugin.common.BinaryMessenger$BinaryMessageHandler {
}
-keep interface io.flutter.plugin.common.BinaryMessenger$BinaryReply {
  public void reply(java.nio.ByteBuffer);
}
-keep interface io.flutter.plugin.common.BinaryMessenger {
  public void send(java.lang.String, java.nio.ByteBuffer);
  public void send(java.lang.String, java.nio.ByteBuffer, io.flutter.plugin.common.BinaryMessenger$BinaryReply);
  public void setMessageHandler(java.lang.String, io.flutter.plugin.common.BinaryMessenger$BinaryMessageHandler);
}
-keep class io.flutter.plugin.common.MethodCall {
  public <init>(java.lang.String, java.lang.Object);
}
-keep interface io.flutter.plugin.common.MethodChannel$Result {
  public void error(java.lang.String, java.lang.String, java.lang.Object);
  public void notImplemented();
  public void success(java.lang.Object);
}
-keep class io.flutter.plugin.common.MethodChannel {
}
-keep @interface kotlin.Deprecated {
  public java.lang.String message();
  public kotlin.ReplaceWith replaceWith();
}
-keep @interface kotlin.ExtensionFunctionType {
}
-keep interface kotlin.Lazy {
  public java.lang.Object getValue();
}
-keep class kotlin.LazyKt {
}
-keep class kotlin.LazyKt__LazyJVMKt {
  public static kotlin.Lazy lazy(kotlin.jvm.functions.Function0);
}
-keep @interface kotlin.Metadata {
  public int[] bv();
  public java.lang.String[] d1();
  public java.lang.String[] d2();
  public int k();
  public int[] mv();
  public int xi();
}
-keep class kotlin.Pair {
  public java.lang.Object component1();
  public java.lang.Object component2();
}
-keep class kotlin.Result$Companion {
}
-keep class kotlin.Result {
  public static java.lang.Object constructor-impl(java.lang.Object);
  public static java.lang.Throwable exceptionOrNull-impl(java.lang.Object);
  kotlin.Result$Companion Companion;
}
-keep class kotlin.ResultKt {
  public static java.lang.Object createFailure(java.lang.Throwable);
  public static void throwOnFailure(java.lang.Object);
}
-keep class kotlin.TuplesKt {
  public static kotlin.Pair to(java.lang.Object, java.lang.Object);
}
-keep class kotlin.Unit {
  kotlin.Unit INSTANCE;
}
-keep class kotlin.collections.CollectionsKt {
}
-keep class kotlin.collections.CollectionsKt__IterablesKt {
  public static int collectionSizeOrDefault(java.lang.Iterable, int);
}
-keep class kotlin.collections.CollectionsKt___CollectionsKt {
  public static java.lang.Object single(java.util.List);
}
-keep class kotlin.collections.IntIterator {
  public int nextInt();
}
-keep class kotlin.collections.MapsKt {
}
-keep class kotlin.collections.MapsKt__MapsKt {
  public static java.util.Map mapOf(kotlin.Pair[]);
}
-keep interface kotlin.coroutines.Continuation {
  public kotlin.coroutines.CoroutineContext getContext();
  public void resumeWith(java.lang.Object);
}
-keep class kotlin.coroutines.ContinuationKt {
  public static kotlin.coroutines.Continuation createCoroutine(kotlin.jvm.functions.Function1, kotlin.coroutines.Continuation);
}
-keep interface kotlin.coroutines.CoroutineContext {
}
-keep class kotlin.coroutines.EmptyCoroutineContext {
  kotlin.coroutines.EmptyCoroutineContext INSTANCE;
}
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt {
}
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsJvmKt {
  public static kotlin.coroutines.Continuation intercepted(kotlin.coroutines.Continuation);
}
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt {
  public static java.lang.Object getCOROUTINE_SUSPENDED();
}
-keep class kotlin.coroutines.jvm.internal.ContinuationImpl {
  public <init>(kotlin.coroutines.Continuation);
  protected java.lang.Object invokeSuspend(java.lang.Object);
}
-keep @interface kotlin.coroutines.jvm.internal.DebugMetadata {
  public java.lang.String c();
  public java.lang.String f();
  public int[] i();
  public int[] l();
  public java.lang.String m();
  public java.lang.String[] n();
  public java.lang.String[] s();
}
-keep class kotlin.coroutines.jvm.internal.DebugProbesKt {
  public static void probeCoroutineSuspended(kotlin.coroutines.Continuation);
}
-keep interface kotlin.coroutines.jvm.internal.SuspendFunction {
}
-keep class kotlin.coroutines.jvm.internal.SuspendLambda {
  public <init>(int, kotlin.coroutines.Continuation);
  public kotlin.coroutines.Continuation create(java.lang.Object, kotlin.coroutines.Continuation);
  protected java.lang.Object invokeSuspend(java.lang.Object);
}
-keep class kotlin.io.ByteStreamsKt {
  public static long copyTo$default(java.io.InputStream, java.io.OutputStream, int, int, java.lang.Object);
}
-keep class kotlin.io.CloseableKt {
  public static void closeFinally(java.io.Closeable, java.lang.Throwable);
}
-keep class kotlin.io.FilesKt {
}
-keep class kotlin.io.FilesKt__FileReadWriteKt {
  public static void writeText$default(java.io.File, java.lang.String, java.nio.charset.Charset, int, java.lang.Object);
}
-keep @interface kotlin.jvm.JvmName {
  public java.lang.String name();
}
-keep @interface kotlin.jvm.JvmStatic {
}
-keep interface kotlin.jvm.functions.Function0 {
  public java.lang.Object invoke();
}
-keep interface kotlin.jvm.functions.Function1 {
  public java.lang.Object invoke(java.lang.Object);
}
-keep interface kotlin.jvm.functions.Function2 {
  public java.lang.Object invoke(java.lang.Object, java.lang.Object);
}
-keep class kotlin.jvm.internal.CallableReference {
  java.lang.Object receiver;
}
-keep class kotlin.jvm.internal.FunctionReferenceImpl {
  public <init>(int, java.lang.Object, java.lang.Class, java.lang.String, java.lang.String, int);
}
-keep class kotlin.jvm.internal.Intrinsics {
  public static boolean areEqual(java.lang.Object, java.lang.Object);
  public static void checkNotNull(java.lang.Object);
  public static void checkNotNullExpressionValue(java.lang.Object, java.lang.String);
  public static void checkNotNullParameter(java.lang.Object, java.lang.String);
  public static void checkParameterIsNotNull(java.lang.Object, java.lang.String);
  public static void throwNpe();
}
-keep class kotlin.jvm.internal.Lambda {
  public <init>(int);
}
-keep class kotlin.jvm.internal.Ref$ObjectRef {
  public <init>();
  java.lang.Object element;
}
-keep class kotlin.jvm.internal.Ref {
}
-keep @interface kotlin.jvm.internal.SourceDebugExtension {
  public java.lang.String[] value();
}
-keep class kotlin.jvm.internal.StringCompanionObject {
  kotlin.jvm.internal.StringCompanionObject INSTANCE;
}
-keep class kotlin.ranges.IntRange {
}
-keep class kotlin.ranges.RangesKt {
}
-keep class kotlin.ranges.RangesKt___RangesKt {
  public static kotlin.ranges.IntRange until(int, int);
}
-keep class kotlin.text.Charsets {
  java.nio.charset.Charset US_ASCII;
}
-keep class kotlin.text.StringsKt {
}
-keep class kotlin.text.StringsKt__StringsJVMKt {
  public static boolean startsWith$default(java.lang.String, java.lang.String, boolean, int, java.lang.Object);
}
-keep class kotlin.time.Duration$Companion {
}
-keep class kotlin.time.Duration {
  kotlin.time.Duration$Companion Companion;
}
-keep class kotlin.time.DurationKt {
  public static long toDuration(int, kotlin.time.DurationUnit);
}
-keep enum kotlin.time.DurationUnit {
  kotlin.time.DurationUnit SECONDS;
}
-keep class kotlinx.coroutines.BuildersKt {
  public static kotlinx.coroutines.Deferred async(kotlinx.coroutines.CoroutineScope, kotlin.coroutines.CoroutineContext, kotlinx.coroutines.CoroutineStart, kotlin.jvm.functions.Function2);
  public static java.lang.Object runBlocking(kotlin.coroutines.CoroutineContext, kotlin.jvm.functions.Function2);
}
-keep class kotlinx.coroutines.CancellableContinuation$DefaultImpls {
  public static boolean cancel$default(kotlinx.coroutines.CancellableContinuation, java.lang.Throwable, int, java.lang.Object);
}
-keep interface kotlinx.coroutines.CancellableContinuation {
  public void invokeOnCancellation(kotlin.jvm.functions.Function1);
  public void resume(java.lang.Object, kotlin.jvm.functions.Function1);
}
-keep class kotlinx.coroutines.CancellableContinuationImpl {
  public <init>(kotlin.coroutines.Continuation, int);
  public java.lang.Object getResult();
  public void initCancellability();
}
-keep class kotlinx.coroutines.CoroutineDispatcher {
}
-keep interface kotlinx.coroutines.CoroutineScope {
  public kotlin.coroutines.CoroutineContext getCoroutineContext();
}
-keep enum kotlinx.coroutines.CoroutineStart {
  kotlinx.coroutines.CoroutineStart DEFAULT;
  kotlinx.coroutines.CoroutineStart UNDISPATCHED;
}
-keep interface kotlinx.coroutines.Deferred {
  public java.lang.Object await(kotlin.coroutines.Continuation);
}
-keep class kotlinx.coroutines.Dispatchers {
  public static kotlinx.coroutines.MainCoroutineDispatcher getMain();
  public static kotlinx.coroutines.CoroutineDispatcher getUnconfined();
}
-keep class kotlinx.coroutines.ExecutorsKt {
  public static kotlinx.coroutines.CoroutineDispatcher from(java.util.concurrent.Executor);
}
-keep class kotlinx.coroutines.Job$DefaultImpls {
  public static void cancel$default(kotlinx.coroutines.Job, java.util.concurrent.CancellationException, int, java.lang.Object);
}
-keep interface kotlinx.coroutines.Job {
}
-keep class kotlinx.coroutines.MainCoroutineDispatcher {
}
-keep class kotlinx.coroutines.TimeoutKt {
  public static java.lang.Object withTimeout-KLykuaI(long, kotlin.jvm.functions.Function2, kotlin.coroutines.Continuation);
}
-keep @interface org.jetbrains.annotations.NotNull {
}
-keep @interface org.jetbrains.annotations.Nullable {
}
-keeppackagenames androidx.concurrent.futures
