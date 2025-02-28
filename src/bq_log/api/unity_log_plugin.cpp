#include "UnityPluginAPI/IUnityLog.h"
#include <bq_log/bq_log.h>
static IUnityLog* s_Logger;

static void InitBqLog();
static void UnInitBqLog();
static bq::Log GetBqLog();

static void OnBqLog(uint64_t logId, int32_t categoryIndex, int32_t logLevel, 
	const char* content, int32_t length)
{
	(void)length;
	(void)categoryIndex;
	(void)logId;

	switch (logLevel) {
	case (int32_t)bq::ELogLevel::verbose:
	case (int32_t)bq::ELogLevel::debug:
	case (int32_t)bq::ELogLevel::info:
		UNITY_LOG(s_Logger, content);
		break;
	case (int32_t)bq::ELogLevel::warning:
		UNITY_LOG_WARNING(s_Logger, content);
		break;
	case (int32_t)bq::ELogLevel::error:
	case (int32_t)bq::ELogLevel::fatal:
		UNITY_LOG_ERROR(s_Logger, content);
		break;
	default:
		break;
	}
}

bq::Log GetBqLog() { 
	return bq::Log::get_log_by_name("UnityLog"); 
}

#define QLOG(msg)	UNITY_WRAP_CODE(UNITY_LOG(s_Logger,msg);GetBqLog().info(msg))
#define QWARN(msg)	UNITY_WRAP_CODE(UNITY_LOG_WARNING(s_Logger,msg);GetBqLog().warning(msg))
#define QERROR(msg) UNITY_WRAP_CODE(UNITY_LOG_ERROR(s_Logger,msg);GetBqLog().error(msg))

void InitBqLog() {
	bq::string config = R"(
			appenders_config.appender_0.type=console
			appenders_config.appender_0.time_zone=default local time
			appenders_config.appender_0.levels=all
			appenders_config.appender_0.file_name=CCLog/normal
			appenders_config.appender_0.is_in_sandbox=false
			appenders_config.appender_0.max_file_size=10000000
			appenders_config.appender_0.expire_time_days=10
			appenders_config.appender_0.capacity_limit=200000000
					
			appenders_config.appender_1.type=text_file
			appenders_config.appender_1.time_zone=default local time
			appenders_config.appender_1.levels=all
			appenders_config.appender_1.file_name=CCLog/normal
			appenders_config.appender_1.is_in_sandbox=false
			appenders_config.appender_1.max_file_size=1000000000
			appenders_config.appender_1.expire_time_days=10
			appenders_config.appender_1.capacity_limit=10000000000
					
			appenders_config.appender_3409.type=compressed_file
			appenders_config.appender_3409.time_zone=default local time
			appenders_config.appender_3409.levels=all
			appenders_config.appender_3409.file_name=CCLog/normal
			appenders_config.appender_3409.is_in_sandbox=false
			appenders_config.appender_3409.max_file_size=1000000000
			appenders_config.appender_3409.expire_time_days=10
			appenders_config.appender_3409.capacity_limit=8000000000

            log.buffer_size=65535
            log.reliable_level=normal
			log.thread_mode=independent
			log.print_stack_levels=[debug,warning,error,fatal]
    )";

	if (GetBqLog().is_valid()) {
		return;
	}

	bq::Log l = bq::Log::create_log("UnityLog", config);
	l.enable_auto_crash_handle();

	bq::Log::register_console_callback(&OnBqLog);
}

void UnInitBqLog() {
	bq::Log l = GetBqLog();
	l.force_flush_all_logs();
	l.uninit();
}


// This event trigger when unity unload your plugin
extern "C" {

 
// This event trigger once unity load your plugin
void 
UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API 
UnityPluginLoad(IUnityInterfaces* pInterfaces)
{
    s_Logger = pInterfaces->Get<IUnityLog>();
	InitBqLog();
    UNITY_LOG(s_Logger, "Native Log Plugin load");
}

void 
UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API 
UnityPluginUnload()
{
    UNITY_LOG(s_Logger, "Native Log Plugin unload");
    s_Logger = nullptr;
	UnInitBqLog();
}
 


}
