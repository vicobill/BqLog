#include "UnityPluginAPI/IUnityLog.h"
#include <bq_log/bq_log.h>
#include <stdint.h>

static IUnityLog* s_Logger;

static void InitBqLog();
static void UnInitBqLog();
static bq::log GetBqLog();

static void OnBqLog(uint64_t logId, int categoryIndex, bq::log_level logLevel, 
	const char* content, int length)
{
	(void)length;
	(void)categoryIndex;
	(void)logId;

	switch (logLevel) {
	case bq::log_level::verbose:
	case bq::log_level::debug:
	case bq::log_level::info:
		UNITY_LOG(s_Logger, content);
		break;
	case bq::log_level::warning:
		UNITY_LOG_WARNING(s_Logger, content);
		break;
	case bq::log_level::error:
	case bq::log_level::fatal:
		UNITY_LOG_ERROR(s_Logger, content);
		break;
	default:
		break;
	}
}

bq::log GetBqLog() { 
	return bq::log::get_log_by_name("UnityLog"); 
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

	bq::log l = bq::log::create_log("UnityLog", config);
	l.enable_auto_crash_handle();

	bq::log::register_console_callback(&OnBqLog);
}

void UnInitBqLog() {
	bq::log l = GetBqLog();
	l.force_flush_all_logs();
	//l.uninit();
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
    UnInitBqLog();
    s_Logger = nullptr;
}
 


}
