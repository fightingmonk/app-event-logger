<?php
/******
tapp-tracker.php

Copyright (c) 2013, Tappister, LLC.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Tappister, LLC nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL TAPPISTER, LLC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
******/

date_default_timezone_set('UTC');

/***
 * Customize this path to define where you want log files written
 *   and how to name them. This sample will create a subdirectory called data_logs
 *   and write to a daily log file within that directory.
 * As this is evaluated for each request, you can create a custom log rotation
 *   simply by changing the date format string.
 ***/
$logFileName = "data_logs/tapp_events_" . date("Y-m-d") . ".log";

/***
 * Read the raw HTTP POST body. 
 ***/
$data = file_get_contents("php://input");
if (! $data) {
	exit();
}

/***
 * Look for a uniqueId sent by the client library
 ***/
$uniqueId = (isset($_POST["unique_id"])) ? $_POST["unique_id"] : "";
if (! $uniqueId)
	$uniqueId = "Unknown";

/***
 * And get the client's IP address
 ***/
$remoteAddr = remote_addr();
if (! $remoteAddr)
	$remoteAddr = "";

/***
 * The client library sends data in the form of event_name[]=value&event_name[]=value&...
 * PHP does us the service of unpacking the events into 
 *   $_POST[event_name]=[value,value,...]
 * However, this doesn't preserve the order of events reported by the client,
 *   which is often critical. So, we will instead decode the raw POST body ourselves
 *   and accumulate sequential log lines into $logData.
 * Note that we are only recording values when the event_name haa a trailing "[]".
 ***/
$logData = "";
foreach (explode("&", $data) as $record) {
	$tokens = array_map("rawurldecode", explode("=", $record, 2));
	if (2 != count($tokens))
		continue;
		
	$type = $tokens[0];
	if ("[]" != substr($type, -2)) 
		continue;
	$type = substr($type, 0, -2);
	if (! $type)
		continue;
		
	$name = $tokens[1];
	if (! $name) $name = "";
	
	$logData .= format_log_line($type, $name);
}

/***
 * generate a comma-separated line of data for the log file
 * date,remote_addr,unique_id,type,name
 ***/
if ($logData) {
	lock_and_write($logData);
}


/***
 * generate a comma-separated line of data for the log file
 * date,remote_addr,unique_id,type,name
 ***/
function format_log_line($type, $name) {
	global $uniqueId, $remoteAddr;
	
	return date("c") . ",${remoteAddr},${uniqueId},${type},${name}\n";
}

/***
 * Optionally create the logging directory, if any, and perform an atomic 
 *   append of $data to the current log file.
 ***/
function lock_and_write($data) {
	global $logFileName;
	
	// ensure the log directory exists
	$dirName = dirname($logFileName);
	if (! file_exists($dirName)) {
		mkdir($dirName);
	}
	
	// optionally create the log file, lock, write, and release
	$h = fopen($logFileName, "ab");
	flock($h, LOCK_EX);
	fseek($h, 0, SEEK_END);
	fwrite($h, $data);
	flock($h, LOCK_UN);
	fclose($h);
}

/***
 * Pay attention to upstream load balancer / proxies when getting the remote IP address.
 ***/
function remote_addr() {
	if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])
	    && $_SERVER['HTTP_X_FORWARTDED_FOR'] != '')
	{
		return $_SERVER['HTTP_X_FORWARDED_FOR'];
	} else {
		return $_SERVER['REMOTE_ADDR'];
	}
}


?>