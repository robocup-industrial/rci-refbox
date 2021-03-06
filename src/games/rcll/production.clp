
;---------------------------------------------------------------------------
;  production.clp - LLSF RefBox CLIPS production phase rules
;
;  Created: Thu Feb 07 19:31:12 2013
;  Copyright  2013  Tim Niemueller [www.niemueller.de]
;  Licensed under BSD license, cf. LICENSE file
;---------------------------------------------------------------------------

(defrule production-start
  (declare (salience ?*PRIORITY_HIGH*))
  ?gs <- (gamestate (phase PRODUCTION) (prev-phase ~PRODUCTION))
  =>
  (modify ?gs (prev-phase PRODUCTION) (game-time 0.0))

  ; trigger machine info burst period
  (do-for-fact ((?sf signal)) (eq ?sf:type machine-info-bc)
    (modify ?sf (count 1) (time 0 0))
  )

  ; Set lights
  (delayed-do-for-all-facts ((?machine machine)) TRUE
    (modify ?machine (desired-lights GREEN-ON))
  )

  ;(assert (attention-message (text "Entering Production Phase")))
)

(defrule prod-machine-down
  (declare (salience ?*PRIORITY_HIGHER*))
  (gamestate (phase PRODUCTION) (state RUNNING) (game-time ?gt))
  ?mf <- (machine (name ?name) (mtype ?mtype)
		  (state ?state&~DOWN) (proc-start ?proc-start)
		  (down-period $?dp&:(<= (nth$ 1 ?dp) ?gt)&:(>= (nth$ 2 ?dp) ?gt)))
  =>
  (bind ?down-time (- (nth$ 2 ?dp) (nth$ 1 ?dp)))
  (printout t "Machine " ?name " down for " ?down-time " sec" crlf)
  (if (eq ?state PROCESSING)
   then
    (modify ?mf (state DOWN) (desired-lights RED-ON) (prev-state ?state)
	    (proc-start (+ ?proc-start ?down-time)))
   else
    (modify ?mf (state DOWN) (prev-state ?state) (desired-lights RED-ON))
  )
)

(defrule prod-machine-up
  (declare (salience ?*PRIORITY_HIGHER*))
  (gamestate (phase PRODUCTION) (state RUNNING) (game-time ?gt))
  ?mf <- (machine (name ?name) (state DOWN) (prev-state ?prev-state&~DOWN)
		  (mps-state-deferred ?mps-state)
		  (down-period $?dp&:(<= (nth$ 2 ?dp) ?gt)))
  =>
  (printout t "Machine " ?name " is up again" crlf)
  (if (eq ?mps-state NONE)
   then (modify ?mf (state ?prev-state) (proc-state DOWN))
   else (modify ?mf (state ?prev-state) (proc-state DOWN)
		(mps-state ?mps-state) (mps-state-deferred NONE))
  )
)

(defrule prod-machine-prepare
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?pf <- (protobuf-msg (type "llsf_msgs.PrepareMachine") (ptr ?p)
		       (rcvd-from ?from-host ?from-port) (client-type ?ct) (client-id ?cid))
  (network-peer (id ?cid) (group ?group))
  =>
  (retract ?pf)
  (bind ?mname (sym-cat (pb-field-value ?p "machine")))
  (bind ?team (sym-cat (pb-field-value ?p "team_color")))
  (if (and (eq ?ct PEER) (neq ?team ?group))
   then
    ; message received for a team over the wrong channel, deny
    (assert (attention-message (team ?group)
	      (text (str-cat "Invalid prepare for team " ?team " of team " ?group))))
   else
    (if (not (any-factp ((?m machine)) (and (eq ?m:name ?mname) (eq ?m:team ?team))))
     then
      (assert (attention-message (team ?team)
		(text (str-cat "Prepare received for invalid machine " ?mname))))
     else
      (printout t "Received prepare for " ?mname crlf)
      (do-for-fact ((?m machine)) (and (eq ?m:name ?mname) (eq ?m:team ?team))
        (if (eq ?m:state IDLE) then
	  (printout t ?mname " is IDLE, processing prepare" crlf)
	  (switch ?m:mtype
            (case BS then
	      (if (pb-has-field ?p "instruction_bs")
	       then
	        (bind ?prepmsg (pb-field-value ?p "instruction_bs"))
		(bind ?side (sym-cat (pb-field-value ?prepmsg "side")))
		(bind ?color (sym-cat (pb-field-value ?prepmsg "color")))
		(printout t "Prepared " ?mname " (side: " ?side ", color: " ?color ")" crlf)
	        (modify ?m (state PREPARED) (bs-side  ?side) (bs-color ?color))
               else
		(modify ?m (state BROKEN)(prev-state ?m:state)
			(broken-reason (str-cat "Prepare received for " ?mname " without data")))
	      )
            )
            (case DS then
	      (if (pb-has-field ?p "instruction_ds")
	       then
	        (bind ?prepmsg (pb-field-value ?p "instruction_ds"))
		(bind ?gate (pb-field-value ?prepmsg "gate"))
		(printout t "Prepared " ?mname " (gate: " ?gate ")" crlf)
	        (modify ?m (state PREPARED) (ds-gate ?gate))
               else
		(modify ?m (state BROKEN) (prev-state ?m:state)
			(broken-reason (str-cat "Prepare received for " ?mname " without data")))
	      )
            )
            (case RS then
	      (if (pb-has-field ?p "instruction_rs")
	       then
	        (bind ?prepmsg (pb-field-value ?p "instruction_rs"))
		(bind ?ring-color (sym-cat (pb-field-value ?prepmsg "ring_color")))
		(if (member$ ?ring-color ?m:rs-ring-colors)
		 then
		  (printout t "Prepared " ?mname " (ring color: " ?ring-color ")" crlf)
	          (modify ?m (state PREPARED) (rs-ring-color ?ring-color))
                 else
		  (modify ?m (state BROKEN) (prev-state ?m:state)
			  (broken-reason (str-cat "Prepare received for " ?mname
						  " for invalid ring color (" ?ring-color ")")))
                )
               else
		(modify ?m (state BROKEN) (prev-state ?m:state)
			(broken-reason (str-cat "Prepare received for " ?mname " without data")))
              )
            )
            (case CS then
	      (if (pb-has-field ?p "instruction_cs")
	       then
	        (bind ?prepmsg (pb-field-value ?p "instruction_cs"))
		(bind ?cs-op (sym-cat (pb-field-value ?prepmsg "operation")))
		(switch ?cs-op

		  (case RETRIEVE_CAP then
		    (if (not ?m:cs-retrieved)
		     then
 		      (printout t "Prepared " ?mname " (" ?cs-op ")" crlf)
	              (modify ?m (state PREPARED) (cs-operation ?cs-op))
                     else
		      (modify ?m (state BROKEN) (prev-state ?m:state)
			      (broken-reason (str-cat "Prepare received for " ?mname ": "
						      "cannot retrieve while already holding")))
                    )
                  )
		  (case MOUNT_CAP then
		    (if ?m:cs-retrieved
		     then
 		      (printout t "Prepared " ?mname " (" ?cs-op ")" crlf)
	              (modify ?m (state PREPARED) (cs-operation ?cs-op))
                     else
		      (modify ?m (state BROKEN) (prev-state ?m:state)
			      (broken-reason (str-cat "Prepare received for " ?mname
						      ": cannot mount without cap")))
                    )
		  )
                )
               else
		(modify ?m (state BROKEN) (prev-state ?m:state)
			(broken-reason (str-cat "Prepare received for " ?mname " without data")))
	      )
            )
          )
        )
      )
    )
  )
)


; **** Machine state processing

(defrule prod-proc-state-idle
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state IDLE) (proc-state ~IDLE))
  =>
  (printout t "Machine " ?n " switching to IDLE state" crlf)
  (modify ?m (proc-state IDLE) (desired-lights GREEN-ON))
  (mps-reset (str-cat ?n))
)

(defrule prod-proc-state-prepared-bs
  "BS station goes directly to processing"
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype BS) (state PREPARED) (proc-state ~PREPARED))
  =>
  (printout t "Machine " ?n " switching directly to PROCESSING on prepare" crlf)
  (modify ?m (state PROCESSING) (proc-state PREPARED) (desired-lights GREEN-BLINK)
	  (prep-blink-start ?gt))
)

(defrule prod-proc-state-prepared
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype ?t) (state PREPARED) (proc-state ~PREPARED))
  =>
  (printout t "Machine " ?n " of type " ?t " switching to PREPARED state" crlf)
  (modify ?m (proc-state PREPARED) (desired-lights GREEN-BLINK)
	  (prep-blink-start ?gt))
)

(defrule prod-proc-state-prepared-stop-blinking
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state PREPARED|PROCESSING)
		 (actual-lights GREEN-BLINK) (desired-lights GREEN-BLINK)
		 (prep-blink-start ?bs&:(timeout-sec ?gt ?bs ?*PREPARED-BLINK-TIME*)))
  =>
  (printout t "Machine " ?n " in PREPARED state stopping blinking" crlf)
  (modify ?m (desired-lights GREEN-ON))
)

(defrule prod-proc-state-processing-bs
  "BS must be instructed to dispense base for processing"
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype BS) (state PROCESSING) (proc-state ~PROCESSING)
		 (bs-side ?side) (bs-color ?color))
  =>
  (printout t "Machine " ?n " dispensing " ?color " base on " ?side crlf)
  (modify ?m (proc-state PROCESSING) (desired-lights GREEN-ON YELLOW-ON))
  ; TODO: (mps-instruct DISPENSE-BASE ?side ?color)
  (mps-bs-dispense (str-cat ?n) (str-cat ?color) (str-cat ?side))
)

(defrule prod-proc-state-processing-ds
  "BS must be instructed to dispense base for processing"
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype DS) (state PROCESSING) (proc-state ~PROCESSING)
		 (ds-gate ?gate))
  =>
  (printout t "Machine " ?n " processing to gate " ?gate crlf)
  (modify ?m (proc-state PROCESSING) (desired-lights GREEN-ON YELLOW-ON))
  (mps-ds-process (str-cat ?n) ?gate)
)

(defrule prod-proc-state-processing-rs-insufficient-bases
  "Must check sufficient number of bases for RS"
  (declare (salience ?*PRIORITY_HIGHER*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype RS) (state PROCESSING) (proc-state ~PROCESSING)
		 (rs-ring-color ?ring-color) (bases-added ?ba) (bases-used ?bu))
  (ring-spec (color ?ring-color)
	     (req-bases ?req-bases&:(> ?req-bases (- ?ba ?bu))))
  =>
  (modify ?m (state BROKEN) (proc-state PROCESSING)
	  (broken-reason (str-cat ?n ": insufficient bases ("
				  (- ?ba ?bu) " < " ?req-bases ")")))
)

(defrule prod-proc-state-processing-rs
  "Instruct RS to mount ring"
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype RS) (state PROCESSING) (proc-state ~PROCESSING)
		 (rs-ring-color ?ring-color) (rs-ring-colors $?ring-colors)
                 (bases-added ?ba) (bases-used ?bu))
  (ring-spec (color ?ring-color) (req-bases ?req-bases&:(>= (- ?ba ?bu) ?req-bases)))
  =>
  (modify ?m (proc-state PROCESSING) (desired-lights GREEN-ON YELLOW-ON))
  (printout t "Mounting ring " ?n " from slide " (member$ ?ring-color ?ring-colors) crlf)
  (mps-rs-mount-ring (str-cat ?n) (member$ ?ring-color ?ring-colors))
)

(defrule prod-proc-state-processing-cs-mount-without-retrieve
  "Process on CS"
  (declare (salience ?*PRIORITY_HIGHER*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype CS) (state PROCESSING) (proc-state ~PROCESSING)
		 (cs-operation MOUNT_CAP) (cs-retrieved FALSE))
  =>
  (modify ?m (state BROKEN) (proc-state PROCESSING)
	  (broken-reason (str-cat ?n ": tried to mount without retrieving")))
)

(defrule prod-proc-state-processing-cs-mount
  "Process on CS"
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype CS) (state PROCESSING) (proc-state ~PROCESSING)
		 (cs-operation ?cs-op))
  =>
  (modify ?m (proc-state PROCESSING) (desired-lights GREEN-ON YELLOW-ON))
  (printout t ?cs-op " on machine " ?n crlf)
  (mps-cs-process (str-cat ?n) (str-cat ?cs-op))
)

(defrule prod-proc-state-processed-ds
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype DS) (state PROCESSED) (proc-state ~PROCESSED))
  =>
  (printout t "Machine " ?n " finished processing, moving to output" crlf)
  (modify ?m (state IDLE) (proc-state PROCESSED))
  (mps-deliver (str-cat ?n))
)

(defrule prod-proc-state-processed-rs
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype RS) (state PROCESSED) (proc-state ~PROCESSED)
		 (rs-ring-color ?ring-color) (bases-used ?bu))
  (ring-spec (color ?ring-color) (req-bases ?req-bases))
  =>
  (printout t "Machine " ?n " finished processing, moving to output" crlf)
  (modify ?m (proc-state PROCESSED) (bases-used (+ ?bu ?req-bases)))
  (mps-deliver (str-cat ?n))
)

(defrule prod-proc-state-processed-cs
  (declare (salience ?*PRIORITY_HIGH*))
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (mtype CS) (state PROCESSED) (proc-state ~PROCESSED)
		 (cs-operation ?cs-op))
  =>
  (printout t "Machine " ?n " finished " ?cs-op crlf)
  (bind ?have-cap (eq ?cs-op RETRIEVE_CAP))
  (modify ?m (proc-state PROCESSED) (cs-retrieved ?have-cap))
  (mps-deliver (str-cat ?n))
)

;(defrule prod-proc-state-processed
;  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
;  ?m <- (machine (name ?n) (state PROCESSED) (proc-state ~PROCESSED))
;  =>
;  (printout t "Machine " ?n " finished processing, moving to output" crlf)
;  (modify ?m (proc-state PROCESSED))
;  (mps-deliver (str-cat ?n))
;)

(defrule prod-proc-state-ready-at-output
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state READY-AT-OUTPUT) (proc-state ~READY-AT-OUTPUT))
  =>
  (printout t "Machine " ?n " finished processing, ready at output" crlf)
  (modify ?m (proc-state READY-AT-OUTPUT) (desired-lights YELLOW-ON))
)

(defrule prod-proc-state-retrieval-timeout
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state WAIT-IDLE)
		 (retrieved-at ?r&:(timeout-sec ?gt ?r ?*RETRIEVE-WAIT-IDLE-TIME*)))
  =>
  (printout t "retrieval timeout, going to IDLE" crlf)
  (modify ?m (state IDLE) (proc-state WAIT-IDLE))
)



(defrule prod-proc-state-broken
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state BROKEN) (proc-state ~BROKEN)
		 (team ?team) (broken-reason ?reason))
  =>
  (printout t "Machine " ?n " broken: " ?reason crlf)
  (assert (attention-message (team ?team) (text ?reason)))
  (modify ?m (proc-state BROKEN) (broken-since ?gt)
	  (desired-lights RED-BLINK YELLOW-BLINK))
)

(defrule prod-proc-state-broken-recover
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state BROKEN) (bases-added ?ba)
		 (broken-since ?bs&:(timeout-sec ?gt ?bs ?*BROKEN-DOWN-TIME*)))
  =>
  (printout t "Machine " ?n " recovered" crlf)
  (modify ?m (state IDLE) (prev-state BROKEN) (bases-used ?ba) (cs-retrieved FALSE))
)


; **** MPS state changes

(defrule prod-proc-mps-state-change
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?ms <- (machine-mps-state (name ?n) (state ?mps-state) (num-bases ?num-bases))
  ?m <- (machine (name ?n) (state ?state))
  (or (machine (name ?n) (mps-state ~?mps-state))
      (machine (name ?n) (bases-added ~?num-bases)))
  =>
  (printout t "Machine " ?n " MPS state " ?mps-state " (bases added: " ?num-bases ", state " ?state ")" crlf)
  (retract ?ms)
  (if (eq ?state DOWN)
   then (modify ?m (mps-state-deferred ?mps-state) (bases-added ?num-bases))
   else (modify ?m (mps-state ?mps-state) (bases-added ?num-bases))
  )
)

(defrule prod-proc-mps-state-nochange
  "Cleanup machine states if no change occured"
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?ms <- (machine-mps-state (name ?n) (state ?mps-state))
  ?m <- (machine (name ?n) (mps-state ?mps-state))
  =>
  (retract ?ms)
)

; **** Mapping MPS to machine state reactions

(defrule prod-machine-input-not-prepared
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state ?state&~PREPARED&~BROKEN&~DOWN&~PROCESSING) (mps-state AVAILABLE))
  =>
  (modify ?m (state BROKEN) (prev-state ?state)
	  (broken-reason (str-cat "Input to " ?n " while not prepared " ?state)))
)


(defrule prod-machine-loaded-with-too-many
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state ?state&~BROKEN) (bases-added ?ba)
		 (bases-used ?bu&:(> (- ?ba ?bu) ?*LOADED-WITH-MAX*)))
  =>
  (modify ?m (state BROKEN) (prev-state ?state)
	  (broken-reason (str-cat ?n ": too many additional bases loaded")))
)

(defrule prod-machine-input
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state PREPARED) (mps-state AVAILABLE))
  =>
  (modify ?m (state PROCESSING) (proc-start ?gt) (mps-state AVAILABLE-HANDLED))
)

(defrule prod-machine-proc-done
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state PROCESSING) (mps-state PROCESSED)
		 (proc-time ?pt) (proc-start ?pstart&:(timeout-sec ?gt ?pstart ?pt)))
  =>
  (modify ?m (state PROCESSED))
)

(defrule prod-machine-ready-at-output
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state PROCESSING|PROCESSED|WAIT-IDLE) (mps-state DELIVERED)
		 (proc-time ?pt) (proc-start ?pstart&:(timeout-sec ?gt ?pstart ?pt)))
  =>
  (modify ?m (state READY-AT-OUTPUT))
)

(defrule prod-machine-retrieved
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?m <- (machine (name ?n) (state READY-AT-OUTPUT) (mps-state RETRIEVED)
		 (proc-time ?pt) (proc-start ?pstart&:(timeout-sec ?gt ?pstart ?pt)))
  =>
  (modify ?m (state WAIT-IDLE) (retrieved-at ?gt) (desired-lights YELLOW-BLINK))
)


(defrule prod-pb-recv-SetMachineState
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?pf <- (protobuf-msg (type "llsf_msgs.SetMachineState") (ptr ?p) (rcvd-via STREAM)
		       (rcvd-from ?from-host ?from-port) (client-id ?cid))
  =>
  (bind ?mname (sym-cat (pb-field-value ?p "machine_name")))
  (bind ?state (sym-cat (pb-field-value ?p "state")))
  (printout t "Received state " ?state " for machine " ?mname crlf)
  (do-for-fact ((?m machine)) (eq ?m:name ?mname)
    (assert (machine-mps-state (name ?mname) (state ?state) (num-bases ?m:bases-added)))
  )
)

(defrule prod-pb-recv-MachineAddBase
  (gamestate (state RUNNING) (phase PRODUCTION) (game-time ?gt))
  ?pf <- (protobuf-msg (type "llsf_msgs.MachineAddBase") (ptr ?p) (rcvd-via STREAM)
		       (rcvd-from ?from-host ?from-port) (client-id ?cid))
  =>
  (bind ?mname (sym-cat (pb-field-value ?p "machine_name")))
  (printout t "Add base to machine " ?mname crlf)
  (do-for-fact ((?m machine)) (eq ?m:name ?mname)
    (assert (machine-mps-state (name ?mname) (state ?m:mps-state)
			       (num-bases (+ ?m:bases-added 1))))
  )
)
