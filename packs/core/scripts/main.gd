extends RefCounted
## Entry point for the "core" pack.
##
## Instead of hard-coding cell behaviour in the engine, the core rules are
## registered here as hooks. A DLC can add its own hooks (higher priority) or
## replace the core pack entirely to change how landing on a cell behaves.
##
## Hooks run ONLY on the authoritative server. They must not touch rendering or
## read another player's balance; they only append abstract "effects" that the
## GameController applies and networks safely.

var _pack_id: String = "core"

func setup(pack_id: String) -> void:
	_pack_id = pack_id
	# Vanilla monetary/property rules are validated by GameController.
	# DLC may still register on_land/on_roll/on_purchase hooks through EventBus.
