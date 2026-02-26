;; modes: inm
;; Requirements:    [IFPS.FUNC.RXMSG.IFPL.PROC.032]
;; Purpose:         Verify that an ICHG message with NO REVAL_ERRORs and NO PROPOSED_ROUTE is sent to ETFMS
;;                  and that a "TO" checkpoint (Transmit_OK) is stored in Flight Plan History if and when a FPL's
;;                  status changes from REVAL_SUSPENDED to COMPLIANT as a result of an IFPL input message to the IFPS.
;; Input:           FPL with invalid route and restriction checking OFF. It becomes REVAL_SUSPENDED when RS Check is turned ON.
;;                  Subsequent correction IFPL message with valid route that makes the FPL COMPLIANT.
;; Expected output: ICHG message sent to ETFMS with NO REVAL_ERRORs and NO PROPOSED_ROUTE.
;;                  Checkpoint "TO" for FP with Mode Automatic stored in FP History.

;; The revalidation tests assume the following integer parameter values:

;;                           Value  Default   Min    Max    Units
;;                          ---------------------------------------
;; REPROCESS_FIRST            720     720      30    1440  Minutes
;; REPROCESS_FREQUENCY         30      30      30    1440  Minutes
;; REPROCESS_LAST               0       0       0    1440  Minutes
;; SUSPENSION_LAST             60      60       0    1440  Minutes
;; FPD_CLOSE_TIME             480     480       0    1440  Minutes

(standard.debug_switch_push "REGISTERCALLBACK.IMPLEMENTATION.SUPPRESS_CLIENT_CLEANUP" T T PROCESSES_TO_KICK "query_handler_process")

(standard.time_control "981105 003100" T) ; AVOID using BACKWARD TIME ! See how_to_test_guidelines_inm
(standard.trace T F)

;; During injection of flights, restriction checking is turned off. The flights violate restrictions.
;; Once injected, restriction checking is turned back on. The revalidation process then finds the restriction errors.

(flight_services.set_boolean_param DISABLE_RS_CHECK T)


;; ACFT01 will be revalidated and become REVAL_SUSPENDED.
;; An associated IFPL with a route change will then be simulated, resulting in the FPL becoming UPDATED.
;; A message must be sent to TACT to confirm that the flight plan is now valid.

(ifps_services.inject_flight
"(FPL-ACFT01-IN
-LJ35/M-SWY/CL
-LESO0900
-N0400F360 BTZ G17 AGN UA25 DIN DCT PEPAL DCT TUR TR28 AVD DCT
-LFGP0130 LFPT
-RMK/TEST -E/0412 P/8 R/VE S/PD J/LF D/0)")


;; Turn on restriction checking.
;; During revalidation, the flight plan will be found invalid and become REVAL_SUSPENDED.

(flight_services.set_boolean_param DISABLE_RS_CHECK F)

(standard.time_control "981105 010100")

;; Revalidation was scheduled at 010000.
;; Check that the FPD status has become REVAL_SUSPENDED after revalidation.

(ifps_fpd_services.get_fpd
 acft_id  "ACFT01"
 fpd_var acft01_fpd_)

(ifps_fpd_services.check_fpd
 "ACFT01 has status REVAL_SUSPENDED"
 acft01_fpd_1
 status_fpd  equal  REVAL_SUSPENDED)


;; Inject the same IFPL with the valid proposed route. Makes FPL valid.

(ifps_services.inject_flight
"(FPL-ACFT01-IN
-LJ35/M-SWY/CL
-LESO0900
-N0400F360 BTZ1A BTZ UB198 BDX TB19 CGC UA25 DIN/N0400F350 DCT PEPAL DCT TUR TR28 AVD DCT
-LFGP0130 LFPT
-RMK/TEST -E/0412 P/8 R/VE S/PD J/LF D/0)")


;; Check that 2 ICHG messages were sent to TACT.
;; Only one had REVAL errors and a PROPOSED ROUTE at reval time 01:00.
;; Hence, the other one at 01:01 had neither REVAL errors nor a PROPOSED ROUTE.

;; CHG resulting from revalidation not received in INM mode
(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (ifps_output_messages.count
     "Only the FPL validation ICHG receiven in INM mode: "
     queue_type  tact
     arc_id      "ACFT01"
     title       "ICHG"
     nb_times    1)

    (ifps_output_messages.count
     "No ICHG msgs with REVAL_ERRORs received in INM mode: "
     queue_type  tact
     arc_id      "ACFT01"
     title       "ICHG"
     time_stamp  "981105 0100"
     other_info  "-REVAL_ERROR"
     iregex      "PROPOSED_ROUTE"
     nb_times    0)
  )

  (progn
    (ifps_output_messages.count
     "Count number of ICHG msgs for ACFT01 to TACT: "
     queue_type  tact
     arc_id      "ACFT01"
     title       "ICHG"
     nb_times    2)

    (ifps_output_messages.count
     "Count number of ICHG msgs with REVAL_ERRORs and PROPOSED_ROUTE for ACFT01 to TACT: "
     queue_type  tact
     arc_id      "ACFT01"
     title       "ICHG"
     time_stamp  "981105 0100"
     other_info  "-REVAL_ERROR"
     iregex      "PROPOSED_ROUTE"
     nb_times    1)
  )
)

(ifps_output_messages.count
 "Count number of ICHG msgs for ACFT01 to TACT: "
 queue_type  tact
 arc_id      "ACFT01"
 title       "ICHG"
 time_stamp  "981105 0101"
 nb_times    1)

(ifps_output_messages.count
 "Count number of ICHG msgs with REVAL_ERRORs for ACFT01 to TACT: "
 queue_type  tact
 arc_id      "ACFT01"
 title       "ICHG"
 time_stamp  "981105 0101"
 other_info  "-REVAL_ERROR"
 nb_times    0)

(ifps_output_messages.count
 "Count number of ICHG msgs with PROPOSED_ROUTE for ACFT01 to TACT: "
 queue_type  tact
 arc_id      "ACFT01"
 title       "ICHG"
 time_stamp  "981105 0101"
 iregex      "PROPOSED_ROUTE"
 nb_times    0)


;; Check that the FPD status becomes COMPLIANT

(ifps_fpd_services.get_fpd
 acft_id "ACFT01"
 fpd_var acft01_fpd_)

;; CFMUTACT address not included in INM mode
(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean F)
  (progn
    (ifps_fpd_services.check_fpd
     "ACFT01 has status COMPLIANT and an internal dest address containing CFMUTACT"
     acft01_fpd_1
     status_fpd  equal     COMPLIANT
     set_of_add  contains  "TYPE => INTERNAL, INFO => CFMUTACT")
  )
)

(test.check_natural "Number of FPDs for ACFT01 = 1" acft01_fpd_# 1)

(ifps_fpd_services.get_fpd_id
 fpd_var     acft01_fpd_1
 fpd_id_var  acft01_fpd_id)

(ifps_fph_services.get_fph
 fpd_id_Var  acft01_fpd_id
 fph_var     acft01_fph_)


;; "TO" checkpoint only stored in FPH when in "multi" exec mode.

(standard.check_if (env "EXECUTION_MODE" multi)

  ;; if EXECUTION_MODE = MULTI
  (ifps_fph_services.check_fph
  "ICHG TO (Transmit OK) registered"
  fph_var       acft01_fph_
  checkpoint    TRANSMIT_OK
  mode          AUTO
  acft_id       "ACFT01"
  time_stamp    "1998/11/05 01:01:00"
  msg_title     ICHG) ; Pending check of Trx_Addresses = CFMUTACT when available

  ;; else (if EXECUTION_MODE/=MULTI)
  (standard.comment "Test of TO checkpoint #1 in test_ifps_func_rxmsg_ifpl_proc.el disabled for EXECUTION_MODE = mono")
)


;; Requirements:    [IFPS.FUNC.RXMSG.IFPL.PROC.033]
;;                  !!!!! WARNING: This requirement is under revision.
;; Purpose:         Verify that an update on the EOBT done by an IFPL message
;;                  re-schedules all of the currently scheduled events (if any).
;; Input:           Valid FPL and subsequent associated CNL + IFPL messages with new (valid) EOBT.
;; Expected output: Scheduled events are re-scheduled as a consequence of the new EOBT in the valid IFPL message.

;; The revalidation tests assume the following integer parameter values:

;;                           Value  Default   Min    Max    Units
;;                          ---------------------------------------
;; REPROCESS_FIRST            720     720      30    1440  Minutes
;; REPROCESS_FREQUENCY         30      30      30    1440  Minutes
;; REPROCESS_LAST               0       0       0    1440  Minutes
;; SUSPENSION_LAST             60      60       0    1440  Minutes
;; FPD_CLOSE_TIME             480     480       0    1440  Minutes


(standard.time_control "981105 010500")

;; ACFT02, with EOBT = 0400 will be first revalidated at 01:30:00.

(ifps_services.inject_flight
"(FPL-ACFT02-IN
-LJ35/M-SWY/CL
-LESO0400
-N0400F360 BTZ1A BTZ UB198 BDX TB19 CGC UA25 DIN/N0400F350 DCT PEPAL DCT TUR TR28 AVD DCT
-LFGP0130 LFPT
-RMK/TEST -E/0412 P/8 R/VE S/PD J/LF D/0)")

;; Check that events have been correctly scheduled
(ifps_fpd_services.get_fpd
 acft_id  "ACFT02"
 fpd_var  acft02_fpd_)

(ifps_fpd_services.get_fpd_id
 fpd_var    acft02_fpd_1
 fpd_id_var acft02_fpd_id_1)

(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (flight.construct (ACFT02) f1)
    (flight.check_flight "Check events for ACFT02 at 981105 013000" f1
     TIMERS((IFPS_REVALIDATE_EVENT "98/11/05 01:30:00")
            (IFPS_CLOSE_EVENT "98/11/05 13:54:54")))
  )

  (progn
    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 013000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105013000")

    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 020000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105020000")

    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 023000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105023000")

    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 030000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105030000")

    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 033000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105033000")

    (flight_scheduled_event_services.Check_Event_List
     "Check REVAL event exists for ACFT02 at 981105 040000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Activation  "981105040000")

    (flight_scheduled_event_services.Check_Event_List
     "Check CLOSE event exists for ACFT02 at 981105 133000"
     fpd_id_var  acft02_fpd_id_1
     Kind        Close
     Activation  "981105133000")
  )
)

;; Change EOBT (valid time) with CNL + IFPL and verify that all events above.
;; (Validate & Close) have been re-scheduled.

(standard.time_control "981105 021000")

(ifps_services.inject_flight
 "(CNL-ACFT02-LESO0400-LFGP-0)")

(ifps_services.inject_flight
"(FPL-ACFT02-IN
-LJ35/M-SWY/CL
-LESO0415
-N0400F360 BTZ1A BTZ UB198 BDX TB19 CGC UA25 DIN/N0400F350 DCT PEPAL DCT TUR TR28 AVD DCT
-LFGP0130 LFPT
-RMK/TEST -DOF/981105 -E/0412 P/8 R/VE S/PD J/LF D/0)")


;; Check the scheduled events have been correctly generated.

(ifps_fpd_services.get_fpd
 acft_id  "ACFT02"
 fpd_var  acft02_fpd_)

(test.check_natural "#Number of FPDs for ACFT02" acft02_fpd_# 2)

;; Verify that the first FPL's events have been canceled:

(ifps_fpd_services.get_fpd_id
 fpd_var     acft02_fpd_1
 fpd_id_var  acft02_fpd_id_1)

;; In INM mode, the Arcid ACFT02 already contains the information of acft02_fpd_2
(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (flight.construct (ACFT02) f1)
    (flight.check_flight "Check events for ACFT02 at 981105 013000" f1
     TIMERS((IFPS_REVALIDATE_EVENT "98/11/05 02:15:00")
            (IFPS_CLOSE_EVENT "98/11/05 14:09:54")))
  )

  (progn
    (flight_scheduled_event_services.Check_Event_List
     "Check NO REVAL event exists for FPD_1 of ACFT02"
     fpd_id_var  acft02_fpd_id_1
     Kind        Validate
     Not_Present)

    (flight_scheduled_event_services.Check_Event_List
     "Check NO CLOSE event exists for FPD_1 of ACFT02"
     fpd_id_var  acft02_fpd_id_1
     Kind        Close
     Not_Present)
  )
)

;; Whilst the events of the second FPL are of course scheduled according to its EOBT:

(ifps_fpd_services.get_fpd_id
 fpd_var     acft02_fpd_2
 fpd_id_var  acft02_fpd_id_2)

(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (flight.construct (ACFT02) f1)
    (flight.check_flight "Check events for ACFT02 at 981105 021500" f1
     TIMERS((IFPS_REVALIDATE_EVENT "98/11/05 02:15:00")
            (IFPS_CLOSE_EVENT "98/11/05 14:09:54")))
  )

  (progn
    (flight_scheduled_event_services.Check_Event_List
     "Check reval event exists for ACFT02 at 981105 021500"
     fpd_id_var  acft02_fpd_id_2
     Kind        Validate
     Activation  "981105021500")

    (flight_scheduled_event_services.Check_Event_List
     "Check reval event exists for ACFT02 at 981105 024500"
     fpd_id_var  acft02_fpd_id_2
     Kind        Validate
     Activation  "981105024500")

    (flight_scheduled_event_services.Check_Event_List
     "Check reval event exists for ACFT02 at 981105 031500"
     fpd_id_var  acft02_fpd_id_2
     Kind        Validate
     Activation  "981105031500")

    (flight_scheduled_event_services.Check_Event_List
     "Check reval event exists for ACFT02 at 981105 034500"
     fpd_id_var  acft02_fpd_id_2
     Kind        Validate
     Activation  "981105034500")

    (flight_scheduled_event_services.Check_Event_List
     "Check reval event exists for ACFT02 at 981105 041500"
     fpd_id_var  acft02_fpd_id_2
     Kind        Validate
     Activation  "981105041500")

    (flight_scheduled_event_services.Check_Event_List
     "Check CLOSE event exists for ACFT02 at 981105 1345000"
     fpd_id_var  acft02_fpd_id_2
     Kind        Close
     Activation  "981105134500")
  )
)

;;
;;
;;  Requirements are undocumented.  This script verifies that EOBT is not updated on associating FPLs.
;;
;;  Historic relevent I2s: 28407, 32358
;;
;; Cycle 239 is no longer available. This test has been migrated to 184
;; Dates shifted from 030123 to 981111

;; Use force_periodic_event_at to perform a large time jump
(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (flight.force_periodic_event_at "98/11/11 08:00:00")
  )
  )

(flight_corba_services.add
 context    ("1234" "tester" "bla" CHMI "bla" "bla" "bla" "bla" "bla" IFPS)
 polling_rate_var   my_polling_rate
 return_status_var  my_status)

(flight_corba_services.check_return_status
 "Return Status"
 my_status  (T ""))

(standard.time_control "981111 080000")
(standard.trace T F)
(services.continue_on_error T)
(flight_services.set_boolean_param DISABLE_AIRAC_CHECK T)

;; LIME15K & LIME5K
;; LIME15K crosses >15000 airspaces and >5000 duplicates
;; LIME5K crosses >5000 airspaces and <5000 duplicates
;; Check handling of crossing large number of airspaces
;; The system does not expect profiles to cross more than 5000 airspaces (invalidates with an error) and cannot handle profiles that
;; cross more than 5000 duplicate airspaces. In either case an error is raised, but if there are more than 5000 duplicates
;; the flight plan cannot be plotted on the map.
;; See I2 115060 for details.
;; [IFPS.FUNC.RXMSG.IFPL.PROC.001] no association
(ifps_services.inject_flight
 "(FPL-LIME15K-IS
 -B763/H-SYW/CL
 -LIBF1700
 -N0465F060 EKTOL DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT BEMVO DCT OMIRO DCT
 DCT EGN
-LGEL0841
-DOF/981111
-RMK/DOD PATROLLING ITALY IN B763)")


(ifps_services.inject_flight
 "(FPL-LIME5K-IS
 -B763/H-SYW/CL
 -LIBF1700
 -N0465F060 EKTOL DCT
 BEMVO DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT OMIRO DCT
 BEMVO DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO DCT BEMVO DCT INTER DCT PARNA DCT OMIRO
 DCT EGN
-LGEL0841
-DOF/981111
-RMK/DOD PATROLLING ITALY IN B763)")

;; LONG1 produces a very long ADEXP message for transmission (longer than 10240 characters)
;; Verify that the resulting ADEXP message has leading space characters stripped.
(ifps_services.inject_flight
 "(FPL-LONG1-IS
-B742/H-E1HIWY/S
-ESNN0100
-N0530F240 XODRO DCT HMR/N0530F280 UT31 NOSLI UN850
 WRB UB230 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1
CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1
CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1
CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1
CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1
CDC/N0450F190 G35 DIRKA
-LMML2300
-EET/ESRR0022 35N019W0248 4844N00956E0212
 COM/OK RMK/LONG ADEXP MESSAGE)
")

;; LONG2 produces a very long ADEXP message for transmission.
;; The message produced is just less than the AFTN limit of 10240 characters.
;; However, when the long lines are wrapped to not exceed the maximum AFTN line length, the additional LF characters cause
;; the message to be longer than the AFTN limit of 10240 characters and so must be compressed.
;; Verify that the resulting ADEXP message has leading space characters stripped.
;; In INM mode, the CFMUTACT address is not included in the message. Hence, additional characters are added to preserve
;; this behaviour.

(standard.check_if (opstat "P:INM_MODE.ACTIVATED" boolean T)
  (progn
    (ifps_services.inject_flight
     "(FPL-LONG2-IS
    -B742/H-E1HIWY/S
    -ESNN0100
    -N0530F240 XODRO DCT HMR/N0530F280 UT31 NOSLI UN850 WRB UB230 DKB/N0450F190 DCT TGO G5 SPR A1 TOP/N0550F280 UA1
    CDC UG12 TSL UB5 TUXOV/N0450F290 OAT WHERE DO WE GO FROM HERE TOP/N0550F280 GAT UA1
    CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 DCT TGO G5 SPR A1 TOP/N0550F280 UA1
    CDC/N0450F190 G35 DIRKA
    -LMML1300
    -EET/ESRR0022 35N019W0248 4844N00956E0212
     COM/OK RMK/THIS IS PADDING 12345678901234567890123456789012345678901234567890123456789012345678901234567890
    12345678901234567890123456789012345678901234567
     RMK/BASED ON I2.125259 CHARSFORINMMODE)
    ")
  )

  (progn
    (ifps_services.inject_flight
     "(FPL-LONG2-IS
    -B742/H-E1HIWY/S
    -ESNN0100
    -N0530F240 XODRO DCT HMR/N0530F280 UT31 NOSLI UN850 WRB UB230 DKB/N0450F190 DCT TGO G5 SPR A1 TOP/N0550F280 UA1
    CDC UG12 TSL UB5 TUXOV/N0450F290 OAT WHERE DO WE GO FROM HERE TOP/N0550F280 GAT UA1
    CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 DCT TGO G5 SPR A1 TOP/N0550F280 UA1
    CDC/N0450F190 G35 DIRKA
    -LMML1300
    -EET/ESRR0022 35N019W0248 4844N00956E0212
     COM/OK RMK/THIS IS PADDING 12345678901234567890123456789012345678901234567890123456789012345678901234567890
    12345678901234567890123456789012345678901234567
     RMK/BASED ON I2.125259)
    ")
  )
)



;; check the different EOBT
;
;; Icao-messages
;
;; DLIC001
;; fpl eobt=1700 at 0800
;; fpl eobt=1730 at 0900 (update is expected to be ineffective)
;; [IFPS.FUNC.RXMSG.IFPL.PROC.001] single association
;; [IFPS.FUNC.RXMSG.IFPL.PROC.026] invalid if EOBT update attempted
(ifps_services.inject_flight
"(FPL-DLIC001-IN
     -LJ31/M-SE1HWY/S
     -EDDL1700
     -N0428F230 GMH B1 SIGEN Z719 HAB
     -EDDN0032 EDDM
     -DOF/981111 ORGN/TESTADDR)")

;; DLIC002
;; fpl eobt=1700 at 0800
;; fpl eobt=1630 at 0900 (update is expected to be ineffective)

(ifps_services.inject_flight
"(FPL-DLIC002-IN
     -LJ31/M-SE1HWY/S
     -EDDL1700
     -N0428F230 GMH B1 SIGEN Z719 HAB
     -EDDN0032 EDDM
     -DOF/981111 ORGN/TESTADDR)")

;; Adexp-messages
;
;; DLAD001
;; fpl eobt=1700 at 0800
;; fpl eobt=1730 at 0900 (update is expected to be ineffective)

(ifps_services.inject_flight
"-TITLE   IFPL
-BEGIN    ADDR
            -FAC CFMUTACT
            -FAC EDDZYNYS
            -FAC EDLLZQZX
            -FAC EDDLYQYX
            -FAC EDFFZQZX
            -FAC EDDNYQYX
            -FAC EDZZZQZA
            -FAC EDDAYGLZ
            -FAC EDDXYIYT
-END      ADDR
-ADEP     EDDL
-ADES     EDDN
-ARCID    DLAD001
-ARCTYP   LJ31
-SEQPT    S
-CEQPT    SE1HWY
-ORIGIN   -NETWORKTYPE AFTN -FAC EDDZZPAL
-SRC      FPL
-TTLEET   0032
-RFL      F230
-SPEED    N0428
-FLTRUL   I
-FLTTYP   N
-EOBD     981111
-EOBT     1700
-ROUTE    N0428F230 DCT GMH B1 SIGEN Z719 HAB DCT
-ALTRNT1  EDDM
-BEGIN    RTEPTS
            -PT -PTID EDDL -FL F000 -ETO 040831004300
            -PT -PTID GMH -FL F190 -ETO 040831005340
            -PT -PTID SIGEN -FL F190 -ETO 040831005720
            -PT -PTID TESGA -FL F230 -ETO 040831010125
            -PT -PTID UTUBI -FL F230 -ETO 040831010255
            -PT -PTID HAB -FL F230 -ETO 040831010820
            -PT -PTID EDDN -FL F000 -ETO 040831012340
-END      RTEPTS
-SID      GMH3T
-ATSRT    L603 GMH TESGA
-ATSRT    Z719 TESGA HAB
-STAR     HAB4P")

;; DLAD002
;; fpl eobt=1700 at 0800
;; fpl eobt=1630 at 0900 (update is expected to be ineffective)

(ifps_services.inject_flight
"-TITLE   IFPL
-BEGIN    ADDR
            -FAC CFMUTACT
            -FAC EDDZYNYS
            -FAC EDLLZQZX
            -FAC EDDLYQYX
            -FAC EDFFZQZX
            -FAC EDDNYQYX
            -FAC EDZZZQZA
            -FAC EDDAYGLZ
            -FAC EDDXYIYT
-END      ADDR
-ADEP     EDDL
-ADES     EDDN
-ARCID    DLAD002
-ARCTYP   LJ31
-SEQPT    S
-CEQPT    SE1HWY
-ORIGIN   -NETWORKTYPE AFTN -FAC EDDZZPAL
-SRC      FPL
-TTLEET   0032
-RFL      F230
-SPEED    N0428
-FLTRUL   I
-FLTTYP   N
-EOBD     981111
-EOBT     1700
-ROUTE    N0428F230 DCT GMH B1 SIGEN Z719 HAB DCT
-ALTRNT1  EDDM
-BEGIN    RTEPTS
            -PT -PTID EDDL -FL F000 -ETO 040831004300
            -PT -PTID GMH -FL F190 -ETO 040831005340
            -PT -PTID SIGEN -FL F190 -ETO 040831005720
            -PT -PTID TESGA -FL F230 -ETO 040831010125
            -PT -PTID UTUBI -FL F230 -ETO 040831010255
            -PT -PTID HAB -FL F230 -ETO 040831010820
            -PT -PTID EDDN -FL F000 -ETO 040831012340
-END      RTEPTS
-SID      GMH3T
-ATSRT    L603 GMH TESGA
-ATSRT    Z719 TESGA HAB
-STAR     HAB4P")

(standard.time_control "981111 090000")

(ifps_fpd_services.get_fpd
  acft_id      LIME15K
  fpd_var      lime15k_fpd_)
(test.check_natural "Number of FPDs for LIME15K" lime15k_fpd_# 0)
(ifps_efpm_services.get_efpm
  acft_id      LIME15K
  efpm_var     lime15k_efpm_)
(test.check_natural "Number of EFPMs for LIME15K" lime15k_efpm_# 1)

(ifps_efpm_services.get_efpm_id         efpm_var                    lime15k_efpm_1
                                        efpm_id_var                 lime15k_efpm_id)

(ifps_corba_services.get_invalid_group  efpm_id_var                 lime15k_efpm_id
                                        efpm_group_id_var           lime15k_efpm_group_id)

(ifps_corba_services.get_efpm           efpm_id_var                 lime15k_efpm_id
                                        efpm_group_id_var           lime15k_efpm_group_id
                                        error_list_var              lime15k_error_list
                                        original_message_text_var   lime15k_message_text_var)

(ifps_corba_services.check_message_error_list
 "output error list for LIME15K"
 lime15k_error_list (((EFPM CROSSED_AIRSPACE_LIMIT_EXCEEDED ("7704" "5000")
                            "EFPM330: ROUTE CROSSES TOO MANY AIRSPACES 7704 MORE THAN 5000" 0 0 0 0 F F ErsActive) F)))

;; Try to plot this invalif message that crosses too many airspaces. Curtain derivation was abandoned so it will not be possible.
(ifps_corba_services.get_profiles
  fpl_id_var                    lime15k_efpm_id
  id_kind                       EfpmId
  route_item_list_var           lime15k_ritem_list_
  airspace_profile_list_var     lime15k_asprof_list_
  restriction_profile_list_var  lime15k_rsprof_list_
  return_status_var             lime15k_status
)

(flight_corba_services.check_return_status
  "Return Status"
  lime15k_status  (F "Flight Plan Message has severe errors. Unable to list or plot profile.")
)
(ifps_corba_services.end_group_edit     efpm_group_id_var           lime15k_efpm_group_id
                                        is_escaped                  T
                                        apply_changes               F
                                        return_status_var           end_group_edit_status)
(flight_corba_services.check_return_status
 "Checking status from end_group_edit"
 end_group_edit_status (T ""))

(ifps_fpd_services.get_fpd
  acft_id      LIME5K
  fpd_var      lime5k_fpd_)
(test.check_natural "Number of FPDs for LIME5K" lime5k_fpd_# 0)
(ifps_efpm_services.get_efpm
  acft_id      LIME5K
  efpm_var     lime5k_efpm_)
(test.check_natural "Number of EFPMs for LIME5K" lime5k_efpm_# 1)

(ifps_efpm_services.get_efpm_id         efpm_var                    lime5k_efpm_1
                                        efpm_id_var                 lime5k_efpm_id)


(ifps_corba_services.get_invalid_group  efpm_id_var                 lime5k_efpm_id
                                        efpm_group_id_var           lime5k_efpm_group_id)

(ifps_corba_services.get_efpm           efpm_id_var                 lime5k_efpm_id
                                        efpm_group_id_var           lime5k_efpm_group_id
                                        error_list_var              lime5k_error_list
                                        original_message_text_var   lime5k_message_text_var)

;; Try to plot this invalid message that crosses too many airspaces. Curtain derivation succeeded so profile is plotable.
(ifps_corba_services.get_profiles
  fpl_id_var                    lime5k_efpm_id
  id_kind                       EfpmId
  route_item_list_var           lime5k_ritem_list_
  airspace_profile_list_var     lime5k_asprof_list_
  restriction_profile_list_var  lime5k_rsprof_list_
  return_status_var             lime5k_status
)

(flight_corba_services.check_return_status
  "Return Status"
  lime5k_status  (T "")
)

(ifps_corba_services.end_group_edit     efpm_group_id_var           lime5k_efpm_group_id
                                        is_escaped                  T
                                        apply_changes               F
                                        return_status_var           end_group_edit_status)
(flight_corba_services.check_return_status
 "Checking status from end_group_edit"
 end_group_edit_status (T ""))

;; Check the FPs are valid
;;
(ifps_fpd_services.get_fpd
  acft_id      DLIC001
  fpd_var      dlic001_fpd_)
(test.check_natural "Number of FPDs for DLIC001" dlic001_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLIC001
  efpm_var     dlic001_efpm_)
(test.check_natural "Number of EFPMs for DLIC001" dlic001_efpm_# 0)

(ifps_fpd_services.get_fpd
  acft_id      DLIC002
  fpd_var      dlic002_fpd_)
(test.check_natural "Number of FPDs for DLIC002" dlic002_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLIC002
  efpm_var     dlic002_efpm_)
(test.check_natural "Number of EFPMs for DLIC002" dlic002_efpm_# 0)

(ifps_fpd_services.get_fpd
  acft_id      DLAD001
  fpd_var      dlad001_fpd_)
(test.check_natural "Number of FPDs for DLAD001" dlad001_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLAD001
  efpm_var     dlad001_efpm_)
(test.check_natural "Number of EFPMs for DLAD001" dlad001_efpm_# 0)

(ifps_fpd_services.get_fpd
  acft_id      DLAD002
  fpd_var      dlad002_fpd_)
(test.check_natural "Number of FPDs for DLAD002" dlad002_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLAD002
  efpm_var     dlad002_efpm_)
(test.check_natural "Number of EFPMs for DLAD002" dlad002_efpm_# 0)

;; Inject flight that will /attempt/ (and fail) to delay the EOBT using an ICAO message
;
(ifps_services.inject_flight
"(FPL-DLIC001-IN
     -LJ31/M-SE1HWY/S
     -EDDL1730
     -N0428F230 GMH B1 SIGEN Z719 HAB
     -EDDN0032 EDDM
     -DOF/981111 ORGN/TESTADDR)")

(ifps_fpd_services.get_fpd
  acft_id      DLIC001
  fpd_var      dlic001_fpd_)
(test.check_natural "Number of FPDs for DLIC001" dlic001_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLIC001
  efpm_var     dlic001_efpm_)
(test.check_natural "Number of EFPMs for DLIC001" dlic001_efpm_# 1)

(ifps_efpm_services.check_efpm
 "Ensure that EOBT was not updated on DLIC001"
 dlic001_efpm_1
 eobt       equal "1730"
 Error_Text equal "EFPM405: NOT ALLOWED TO USE A FPL TO UPDATE THE EOBT OF EXISTING FPL: DLIC001 EDDL EDDN 1700 981111. DLA OR CHG IS REQUIRED.")

;; Attempt (and fail) to force a negative delay using an ICAO message
;
(ifps_services.inject_flight
"(FPL-DLIC002-IN
     -LJ31/M-SE1HWY/S
     -EDDL1630
     -N0428F230 GMH B1 SIGEN Z719 HAB
     -EDDN0032 EDDM
     -DOF/981111 ORGN/TESTADDR)")

(ifps_fpd_services.get_fpd    acft_id  "DLIC002"
                              fpd_var  dlic002_fpd_)
(ifps_fpd_services.get_fpd
  acft_id      DLIC002
  fpd_var      dlic002_fpd_)
(test.check_natural "Number of FPDs for DLIC002" dlic002_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLIC002
  efpm_var     dlic002_efpm_)
(test.check_natural "Number of EFPMs for DLIC002" dlic002_efpm_# 1)

(ifps_efpm_services.check_efpm
 "Ensure that EOBT was not updated on DLIC002" dlic002_efpm_1
 eobt       equal "1630"
 error_text equal "EFPM405: NOT ALLOWED TO USE A FPL TO UPDATE THE EOBT OF EXISTING FPL: DLIC002 EDDL EDDN 1700 981111. DLA OR CHG IS REQUIRED.")

;; Inject flight that will /attempt/ (and fail) to delay the EOBT using an ADEXP message
;;
(ifps_services.inject_flight
"-TITLE   IFPL
-BEGIN    ADDR -FAC CFMUTACT
               -FAC EDDZYNYS
               -FAC EDLLZQZX
               -FAC EDDLYQYX
               -FAC EDFFZQZX
               -FAC EDDNYQYX
               -FAC EDZZZQZA
               -FAC EDDAYGLZ
               -FAC EDDXYIYT
-END      ADDR
-ADEP     EDDL
-ADES     EDDN
-ARCID    DLAD001
-ARCTYP   LJ31
-SEQPT    S
-CEQPT    SE1HWY
-ORIGIN   -NETWORKTYPE AFTN -FAC EDDZZPAL
-SRC      FPL
-TTLEET   0032
-RFL      F230
-SPEED    N0428
-FLTRUL   I
-FLTTYP   N
-EOBD     981111
-EOBT     1730
-ROUTE    N0428F230 DCT GMH B1 SIGEN Z719 HAB DCT
-ALTRNT1  EDDM
-BEGIN    RTEPTS -PT -PTID EDDL  -FL F000 -ETO 040831004300
                 -PT -PTID GMH   -FL F190 -ETO 040831005340
                 -PT -PTID SIGEN -FL F190 -ETO 040831005720
                 -PT -PTID TESGA -FL F230 -ETO 040831010125
                 -PT -PTID UTUBI -FL F230 -ETO 040831010255
                 -PT -PTID HAB   -FL F230 -ETO 040831010820
                 -PT -PTID EDDN  -FL F000 -ETO 040831012340
-END      RTEPTS
-SID      GMH3T
-ATSRT    L603 GMH TESGA
-ATSRT    Z719 TESGA HAB
-STAR     HAB4P")

(ifps_fpd_services.get_fpd
  acft_id      DLAD001
  fpd_var      dlad001_fpd_)
(test.check_natural "Number of FPDs for DLAD001" dlad001_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLAD001
  efpm_var     dlad001_efpm_)
(test.check_natural "Number of EFPMs for DLAD001" dlad001_efpm_# 1)
(ifps_efpm_services.check_efpm
 "Ensure that EOBT was not updated on DLAD001"
 dlad001_efpm_1
 eobt       equal "1730"
 error_text equal "EFPM405: NOT ALLOWED TO USE A FPL TO UPDATE THE EOBT OF EXISTING FPL: DLAD001 EDDL EDDN 1700 981111. DLA OR CHG IS REQUIRED.")

;; Attempt (and fail) to force a negative delay using an ADEXP message
;
(ifps_services.inject_flight
"-TITLE   IFPL
-BEGIN    ADDR -FAC CFMUTACT
               -FAC EDDZYNYS
               -FAC EDLLZQZX
               -FAC EDDLYQYX
               -FAC EDFFZQZX
               -FAC EDDNYQYX
               -FAC EDZZZQZA
               -FAC EDDAYGLZ
               -FAC EDDXYIYT
-END      ADDR
-ADEP     EDDL
-ADES     EDDN
-ARCID    DLAD002
-ARCTYP   LJ31
-SEQPT    S
-CEQPT    SE1HWY
-ORIGIN   -NETWORKTYPE AFTN -FAC EDDZZPAL
-SRC      FPL
-TTLEET   0032
-RFL      F230
-SPEED    N0428
-FLTRUL   I
-FLTTYP   N
-EOBD     981111
-EOBT     1630
-ROUTE    N0428F230 DCT GMH B1 SIGEN Z719 HAB DCT
-ALTRNT1  EDDM
-BEGIN    RTEPTS -PT -PTID EDDL  -FL F000 -ETO 040831004300
                 -PT -PTID GMH   -FL F190 -ETO 040831005340
                 -PT -PTID SIGEN -FL F190 -ETO 040831005720
                 -PT -PTID TESGA -FL F230 -ETO 040831010125
                 -PT -PTID UTUBI -FL F230 -ETO 040831010255
                 -PT -PTID HAB   -FL F230 -ETO 040831010820
                 -PT -PTID EDDN  -FL F000 -ETO 040831012340
-END      RTEPTS
-SID      GMH3T
-ATSRT    L603 GMH TESGA
-ATSRT    Z719 TESGA HAB
-STAR     HAB4P")

(ifps_fpd_services.get_fpd
  acft_id      DLAD002
  fpd_var      dlad002_fpd_)
(test.check_natural "Number of FPDs for DLAD002" dlad002_fpd_# 1)
(ifps_efpm_services.get_efpm
  acft_id      DLAD002
  efpm_var     dlad002_efpm_)
(test.check_natural "Number of EFPMs for DLAD002" dlad002_efpm_# 1)
(ifps_efpm_services.check_efpm
 "Ensure that EOBT was not updated on DLAD002"
 dlad002_efpm_1
 eobt       equal "1630"
 error_text equal "EFPM405: NOT ALLOWED TO USE A FPL TO UPDATE THE EOBT OF EXISTING FPL: DLAD002 EDDL EDDN 1700 981111. DLA OR CHG IS REQUIRED.")


;; Check manual processing: attempting to update EOBT with an FPL. EFPM401 error expected.

(ifps_services.inject_flight
 "(FPL-MAN401-IN
       -B744/H-SYW/C
       -EBBR1730
       -N0440F330 DIK DCT TUL
       -LFGB0130
       -ORGN/TESTADDR)")

(ifps_fpd_services.get_fpd
  acft_id   "MAN401"
  fpd_var   man401_fpd_)
(test.check_natural "Number of FPDs for MAN401 " man401_fpd_# 1)

(ifps_services.inject_flight
 "(FPL-MAN401-IN
       -B744/H-SYW/C
       -EBB1830
       -N0440F330 DIK DCT TUL
       -LFGB0130
       -ORGN/TESTADDR)")

(ifps_efpm_services.get_efpm
  acft_id      "MAN401"
  efpm_var     man401_efpm_)
(test.check_natural "Number of EFPMs for MAN401 " man401_efpm_# 1)
(ifps_efpm_services.check_efpm
  "Check fields "
  man401_efpm_1
  title                       equal "IFPL"
  error_text                  equal "SYN70: FIELD TEXT TOO SHORT AT ROW= 3, COL= 9 (ADEP)")
(ifps_efpm_services.get_efpm_id
  efpm_var          man401_efpm_1
  efpm_id_var       man401_efpm_id)
(ifps_corba_services.get_invalid_group
  efpm_id_var           man401_efpm_id
  efpm_group_id_var     man401_efpm_group_id
  return_status_var     man401_status)

(ifps_corba_services.process_flight
 efpm_id_var       man401_efpm_id
 efpm_group_id_var man401_efpm_group_id
 originator        (addraftn TESTADDR)
 operating_mode    MANUAL
 message_text      "(FPL-MAN401-IN
                    -B744/H-SYW/C
                    -EBBR1830
                    -N0440F330 DIK DCT TUL
                    -LFGB0130
                    -ORGN/TESTADDR)"
 error_list_var     man401_error_list
 is_finished_var    man401_is_finished
 check_and_apply    F
 return_status_var  man401_return_status)

(ifps_corba_services.check_message_error_list
 "Error list for manual invalid MAN401 "
 man401_error_list   (((EFPM FPL_UPDATING_EOBT_NOT_ALLOWED ("MAN401" "EBBR" "LFGB" "1730" "981111")
                        "EFPM405: NOT ALLOWED TO USE A FPL TO UPDATE THE EOBT OF EXISTING FPL: MAN401 EBBR LFGB 1730 981111. DLA OR CHG IS REQUIRED." 0 0 0 0 F F ErsActive EMSNONE "") F)))

(test.check_boolean
 "Is Finished"
 man401_is_finished F)

(flight_corba_services.check_return_status
 "Return Status"
 man401_return_status (T ""))

(ifps_corba_services.end_group_edit
 efpm_group_id_var  man401_efpm_group_id
 apply_changes      F
 is_escaped         T
 return_status_var  end_group_edit_status)
(flight_corba_services.check_return_status
 "Checking status from end_group_edit"
 end_group_edit_status (T ""))


(standard.debug_switch_push "ESB_FFR_TEST_READ_WRITE" T T PROCESSES_TO_KICK "flight_process")
(standard.debug_switch_push "ESB_FPL_TEST_READ_WRITE" T T PROCESSES_TO_KICK "flight_process")

;; OPRNM01
;; /OPR field triggering assertion failure on read write test in filing flight reply when it gets truncated
;; and as a result of truncation operator name ends in space; please preserve the formatting of this field
;; I2 117681
(ifps_services.inject_flight
"(FPL-OPRNM01-IN
     -LJ31/M-SE1HWY/S
     -EDDL1700
     -N0428F230 GMH B1 SIGEN Z719 HAB
     -EDDN0032 EDDM
     -DOF/981111 ORGN/TESTADDR
     OPR/AVIA TRAFFIC PERM KGZ 67 2203 GCMR KAZ TR08377123   190317 RUS  FORM R TUR  CASL060  CALLSIGN ATOMIC)")

(ifps_fpd_services.get_fpd
  acft_id      OPRNM01
  fpd_var      oprnm01_fpd_)
(test.check_natural "Number of FPDs for OPRNM01" oprnm01_fpd_# 1)


;; The route below used to give problems when converting the starting invisible item into the curtain structure (F15_Unidentified).
(ifps_services.inject_flight
"(FPL-SWIVEL4-ZM
-ZZZZ/L-GIUVY/C
-ZZZZ2000
-N0130F110 DCT TIDGA/N0140F200B260 IFR OAT GUNKA RUMUK VABOD IVNER
5115N02323E 5124N02315E DISBI 5215N02252E 5228N02253E 5250N02331E
5320N02321E 5356N02308E SUW 5406N02121E 5407N02032E 5400N01941E
5407N02032E 5406N02121E SUW 5356N02308E 5320N02321E 5250N02331E
5228N02253E 5215N02252E DISBI 5124N02315E 5115N02323E IVNER VABOD
RUMUK GUNKA TIDGA SOBSA LUPUK OSDOR L743 TARKA AMGOL TARKA L743
OSDOR
LUPUK SOBSA DCT
-ZZZZ2000 ZZZZ
-DEP/CAMPIA TURZII 4632N02352E DEST/CAMPIA TURZII 4632N02352E
EET/RUMUK0035 IVNER0200 IVNER1000 RUMUK1120 OSDOR1400 OSDOR1800 TYP/MQ9A
ORGN/LROPYOYX PER/B ALTN/CAMPIA TURZII 4632N02352E RMK/STS SOF AEP SP 0934 19
UGS USA 21062019 1111 AP19 US RPA OAT OVER POLAND OAT OVER UKRAINE OAT OVER
ROMANIA POLAND TRA83 TRA84 TRA85 TRA86 TRA87 TRA88 TRA89 TRA90 TRA91 TRA92
ROMANIA LRTRA75A PILOT PHONE 496565613883 RPAS TYPE MQ9A NON RVSM)")

(ifps_efpm_services.get_efpm
  acft_id      SWIVEL4
  efpm_var     SWIVEL4_efpm_)
(test.check_natural "Number of EFPMs for SWIVEL4" SWIVEL4_efpm_# 1)

;; Check LONG1 is a valid message but as IFPS produces a very long ADEXP message for transmission, it must not be sent in an1.
(ifps_efpm_services.get_efpm
  acft_id      LONG1
  efpm_var     the_efpm_)
(test.check_natural "Number of EFPMs for LONG1" the_efpm_# 0)
(ifps_fpd_services.get_fpd
  acft_id      LONG1
  fpd_var      the_fpd_)
(test.check_natural "Number of FPDs for LONG1" the_fpd_# 1)
(ifps_fpd_services.get_fpd_id
 fpd_var     the_fpd_1
 fpd_id_var  the_fpd_id)
(ifps_output_messages.count
 "Output message for LONG1 has leading spaces stripped. Normally FAC and PT would be indented: "
 queue_type        an1
 arc_id            LONG1
 iregex            "^-FAC LSAZZQZX"
 iregex            "^-PT -PTID ESNN -FL F000 -ETO 981112010500"
 nb_times          0)

(flight_corba_services.get_alerts
 context              ("1234" "tester" "bla")
 alert_list_var       the_alert_list
 return_status_var    my_status)

(flight_corba_services.check_return_status
 "Return Status"
 my_status (T ""))

(ifps_corba_services.check_alert_list
 "check the alert list"
 the_alert_list
 (((AA00000001 "")  "98/11/11 08:00:00 from IFPS : A message was rejected by the Remote System. Cause: Message length 16762 greater than network maximum length 10240 Address: AFTN LSAGZQZX LSAZZQZX. Rejected Message is : -TITLE IFPL -BEGIN ADDR -FAC LSAGZQZX -FAC LSAZZQZX -FAC ESUNZQZX -FAC ESNNZPZX -FAC ESNNZTZX -FAC ESOSZQZX -FAC EKKKZQZX -FAC ESMMZQZX -FAC EDDXYIYX -FAC EDZZZQZA -FAC EDFFZQZX -FAC EDUUZQZA -FAC EDYYZQZX -FAC LIMMZQZX -FAC LIIRZEZX -FAC LIRRZQZX -FAC LWSSZQZX -FAC LOVVZQZX -FAC LYBAZQZX -FAC LIBBZQZX -FAC LGGGZQZX -FAC LGGGYKYX -FAC LGMDZQZX -FAC LJLAZQZX -FAC LDZOZQZX -FAC LMMMZRZX -FAC LMMLZAZX -FAC LMMMZPZX -END ADDR -ADEP ESNN -ADES LMML -ARCID LONG1 -ARCTYP B742 -CEQPT E1HIWY -EOBD 981112 -EOBT 0100 -FILTIM 110800 -IFPLID AA00000004 -ORIGIN -NETWORKTYPE AFTN -FAC TESTADDR -SEQPT S -WKTRC H -COM OK -ORGN TESTADDR -RMK LONG ADEXP MESSAGE -SRC FPL -TTLEET 2300 -RFL F240 -SPEED N0530 -FLTRUL I -FLTTYP S -ROUTE N0530F240 XODRO DCT HMR/N0530F280 UT31 NOSLI UN850 WRB UB230 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1 CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1 CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1 CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1 CDC UG12 TSL UB5 TUXOV/N0450F290 UB5 ERL UR11 DKB/N0450F190 4844N00956E TGO G5 SPR A1 TOP/N0550F280 UA1 CDC/N0450F190 G35 DIRKA -EETFIR ESRR 0022 -EETPT GEO01 0212 -EETPT GEO02 0248 -GEO -GEOID GEO01 -LATTD 484400N -LONGTD 0095600E -GEO -GEOID GEO02 -LATTD 350000N -LONGTD 0190000W -GEO -GEOID GEO03 -LATTD 574849N -LONGTD 0151847E -GEO -GEOID GEO04 -LATTD 555355N -LONGTD 0124021E -GEO -GEOID GEO05 -LATTD 484400N -LONGTD 0095600E -RENAME -RENID REN01 -PTID DKB -RENAME -RENID REN02 -P(/)" the_fpd_id)))


;; Check LONG2 has leading spaces stripped. Normally FAC and PT would be indented
(ifps_efpm_services.get_efpm
  acft_id      LONG2
  efpm_var     the_efpm_)
(test.check_natural "Number of EFPMs for LONG2" the_efpm_# 0)
(ifps_fpd_services.get_fpd
  acft_id      LONG2
  fpd_var      the_fpd_)
(test.check_natural "Number of FPDs for LONG2" the_fpd_# 1)
(ifps_output_messages.count  "Output message for LONG2 has leading spaces stripped. Normally FAC and PT would be indented: "
                             queue_type        an1
                             arc_id            LONG2
                             iregex            "^-FAC LSAZZQZX"
                             iregex            "^-PT -PTID ESNN -FL F000 -ETO 981112010500"
                             nb_times          1)

(flight_corba_services.remove
 context    ("1234" "tester" "bla" CHMI "bla" "bla" "bla" "bla" "bla" IFPS)
 return_status_var  my_status)
(flight_corba_services.check_return_status
 "Return Status for removal of tester user: "
 my_status (T ""))

;; I2_134305: Inject an invalid AFP that is converted to APL and goes to invalid queue. Then, inject an FPL before fixing the AFP,
;; the FPL goes also into the invalid queue with EFPM237 error.

(ifps_services.inject_flight
"(AFP-AFPAPL1-IN
-B738/M-SHILWY/SL
-EDDH0900
-GES/092OF380
-N0430F280 LUB UP605 GES UT57 CDA DCT
-EKCH1045
-DOF/981111)")

(ifps_fpd_services.get_fpd
  acft_id      "AFPAPL1"
  fpd_var      the_fpd_)
(test.check_natural "Number of FPDs " the_fpd_# 0)
(ifps_efpm_services.get_efpm
  acft_id      "AFPAPL1"
  efpm_var     the_efpm_)
(test.check_natural "Number of EFPMs " the_efpm_# 1)

(ifps_efpm_services.check_efpm
  "Check fields "
  the_efpm_1
  title                       equal "IAPL"
  The_Flight_Plan_Source_EFPM equal "NETWORK"
  error_text                  equal "PROF191: TTL EET DIFFERENCE > 40%, CALCULATED TTL EET FROM EDDH TO EKCH = 0024 (HHMM).")

(ifps_efpm_services.get_efpm_id
  efpm_var          the_efpm_1
  efpm_id_var       the_efpm_id)
(ifps_corba_services.get_invalid_group
  efpm_id_var           the_efpm_id
  efpm_group_id_var     the_efpm_group_id
  return_status_var     my_status)
(ifps_corba_services.get_efpm
 efpm_id_var               the_efpm_id
 efpm_group_id_var         the_efpm_group_id
 error_list_var            the_error_list
 return_status_var         the_status
 original_message_text_var the_message_text_var)

(test.check_string
   "Checking AFP to APL conversion"
    the_message_text_var
    token_list_mode "(APL-AFPAPL1-IN -B738/M-SHILWY/LS -EDDH0900 -GES/0920F380 -N0430F280 LUB UP605 GES UT57 CDA AFPEND DCT -EKCH1045 -DOF/981111 ORGN/TESTADDR SRC/AFP)")

(ifps_services.inject_flight
 "(FPL-AFPAPL1-IN
-B738/M-SHILWY/LS
-EDDH0850
-N0430F280 LUB UP605 GES UT57 CDA DCT
-EKCH0045
-DOF/981111)")

(ifps_fpd_services.get_fpd
  acft_id      "AFPAPL1"
  fpd_var      the_fpd_)
(test.check_natural "Number of FPDs " the_fpd_# 0)
(ifps_efpm_services.get_efpm
  acft_id      "AFPAPL1"
  efpm_var     the_efpm_)
(test.check_natural "Number of EFPMs " the_efpm_# 2)

(ifps_efpm_services.check_efpm
  "Check Resulting invalid message "
  the_efpm_2
  acft_id         equal   AFPAPL1
  error_text      equal   "EFPM237: MESSAGE MATCHES EXISTING INVALID MESSAGES")

(standard.debug_switch_pop)
