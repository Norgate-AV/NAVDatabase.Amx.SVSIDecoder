MODULE_NAME='mSVSIDecoder'  (
                                dev vdvObject,
                                dev dvPort
                            )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_IP_CLIENT_CHECK = 1

constant integer TCP_PORT    = 50002


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE
volatile long ltIPClientCheck[] = { 3000 }

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile _NAVSocketConnection uIPConnection


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function Send(char cPayload[]) {
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cPayload))
    send_string dvPort, "cPayload"
}

define_function char[NAV_MAX_CHARS] Build(char cPayload[]) {
    return "cPayload, NAV_CR"
}


define_function SetChannel(integer iChannel) {
    Send(Build("'set:', itoa(iChannel)"))
}


define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]

    iSemaphore = true

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'Processing String From ', NAVStringSurroundWith(NAVDeviceToString(dvPort), '[', ']'), '-[', cRxBuffer, ']'")

    while (length_array(cRxBuffer) && NAVContains(cRxBuffer, "NAV_CR")) {
    cTemp = remove_string(cRxBuffer, "NAV_CR", 1)

    if (length_array(cTemp)) {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))
        cTemp = NAVStripCharsFromRight(cTemp, 1)    //Remove delimiter
    }
    }

    iSemaphore = false
}


define_function MaintainIPConnection() {
    if (!uIPConnection.IsConnected) {
    NAVClientSocketOpen(dvPort.PORT, uIPConnection.Address, uIPConnection.Port, IP_TCP)
    }
}

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort,cRxBuffer
    uIPConnection.Port = TCP_PORT

}
(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[dvPort] {
    online: {
    uIPConnection.IsConnected = true
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'SVSI_ONLINE<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")
    }
    string: {
    [vdvObject, DEVICE_COMMUNICATING] = true
    [vdvObject, DATA_INITIALIZED] = true
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device, data.text))
    if (!iSemaphore) { Process() }
    }
    offline: {
    if (data.device.number == 0) {
        uIPConnection.IsConnected = false
        NAVClientSocketClose(data.device.port)
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'SVSI_OFFLINE<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")
    }
    }
    onerror: {
    if (data.device.number == 0) {
        uIPConnection.IsConnected = false
        //NAVClientSocketClose(data.device.port)
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'SVSI_ONERROR<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")
    }
    }
}

data_event[vdvObject] {
    command: {
    stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[3][NAV_MAX_CHARS]

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))

    cCmdHeader = DuetParseCmdHeader(data.text)
    cCmdParam[1] = DuetParseCmdParam(data.text)
    cCmdParam[2] = DuetParseCmdParam(data.text)
    cCmdParam[3] = DuetParseCmdParam(data.text)
    switch (cCmdHeader) {
        case 'PROPERTY': {
        switch (cCmdParam[1]) {
            case 'IP_ADDRESS': {
            uIPConnection.Address = cCmdParam[2]
            NAVTimelineStart(TL_IP_CLIENT_CHECK, ltIPClientCheck, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
            }
            case 'PASSWORD': {

            }
        }
        }
        case 'PASSTHRU': { Build(cCmdParam[1]) }
        case 'SWITCH': {
        SetChannel(atoi(cCmdParam[1]))
        }
    }
    }
}

channel_event[vdvObject,0] {
    on: {

    }
}


define_event timeline_event[TL_IP_CLIENT_CHECK] { MaintainIPConnection() }


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

