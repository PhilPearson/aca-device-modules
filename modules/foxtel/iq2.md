## Control of Foxtel IQ2 via woodside collaboration space logic (https://bitbucket.org/aca/woodside-engine/src/master/modules/woodside/collaboration_space.rb)
* frontend (room/) > collab space logic (System_1)  > receiver logic (Receiver_1) > Globalcache (DigitalIO_1) > Foxtel STB

### Receiver logic commands
* `channel_up`, `channel_down`
* enter channel number (e.g. 9), Foxtel requires minimum 3 digits, entered one at a time: `num(9)`

### Woodside Import script changes
* Reciever _Logic_ to be imported with default settings (Driver: "FoxtelSet Top Box IQ2" / `iq2.rb`)
* Globalcache _Device_ to be imported with default settings and IP of globalcache device