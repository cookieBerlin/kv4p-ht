package pl.brightinventions.slf4android;

/** Stub of the slf4android configuration; log levels do not matter to the generator. */
public final class LoggerConfiguration {
    private static final LoggerConfiguration INSTANCE = new LoggerConfiguration();

    private LoggerConfiguration() {}

    public static LoggerConfiguration configuration() {
        return INSTANCE;
    }

    public LoggerConfiguration setLogLevel(String loggerName, LogLevel level) {
        return this;
    }
}
