## Entity IDs
- Door sensors: binary_sensor.main_panel_{front_door,garage_door,basement_door,sliding_door}
- Motion sensors: binary_sensor.main_panel_{office_motion,family_room_motion}
- Siren: switch.alarm_panel_56ac70_siren
- Alarm panel: alarm_control_panel.home_alarm
- Buzzer play: esphome.konnected_56a4fa_play_rtttl
- Buzzer stop: esphome.konnected_56a4fa_stop_rtttl

## Automation IDs
- alarm_door_trigger, alarm_motion_trigger
- alarm_exit_delay_beep, alarm_entry_delay_beep
- alarm_triggered_siren, alarm_disarmed, alarm_armed_confirmation
- door_chime
