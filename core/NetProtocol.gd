class_name NetProtocol
extends RefCounted
## Named RPC / handshake identifiers shared by client and server.
## Keeping them in one place avoids typos and makes protocol diffs obvious.

const RPC_HELLO := "hello"
const RPC_SUBMIT_JOIN := "submit_join"
const RPC_KICKED := "kicked"
const RPC_RECEIVE_SNAPSHOT := "receive_snapshot"
const RPC_RECEIVE_BALANCE := "receive_balance"
const RPC_RECEIVE_EVENT := "receive_event"
const RPC_RECEIVE_PRIVATE_STATE := "receive_private_state"
const RPC_SERVER_REQUEST_READY := "server_request_ready"
const RPC_SERVER_UPDATE_PROFILE := "server_update_profile"
const RPC_SERVER_REQUEST_START := "server_request_start"
const RPC_SERVER_REQUEST_ROLL := "server_request_roll"
const RPC_SERVER_REQUEST_BUY := "server_request_buy"
const RPC_SERVER_REQUEST_DECLINE := "server_request_decline_purchase"
const RPC_SERVER_REQUEST_BID := "server_request_auction_bid"
const RPC_SERVER_REQUEST_JAIL := "server_request_jail_action"
const RPC_SERVER_REQUEST_BUILD := "server_request_build"
const RPC_SERVER_REQUEST_SELL_BUILDING := "server_request_sell_building"
const RPC_SERVER_REQUEST_SELL_PROPERTY := "server_request_sell_property"
const RPC_SERVER_REQUEST_MORTGAGE := "server_request_mortgage"
const RPC_SERVER_REQUEST_UNMORTGAGE := "server_request_unmortgage"
const RPC_SERVER_REQUEST_BANKRUPTCY := "server_request_bankruptcy"
const RPC_SERVER_PROPOSE_TRADE := "server_propose_trade"
const RPC_SERVER_RESPOND_TRADE := "server_respond_trade"

const EVENT_ROLL := "roll"
const EVENT_TURN := "turn"
const EVENT_ACTION := "action"
const EVENT_TRADE := "trade"
