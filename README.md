fhem Modul for Mediola a.i.o Gateway and Extender


This modul can be used with a Mediola Gateway to send and learn ir/rf codes.


Define

    define <Name> MEDIOLA [IP] [ConfigFile]


    Example:
    define TVSchlafzimmer MEDIOLA 192.168.0.35 mediola/tvsz.json
    attr TVSchlafzimmer ir 00
    attr TVSchlafzimmer rf 01

     
    [IP]
    Set the IP Address of the Mediola GW

    [ConfigFile]
    Set the Path to a Configurationfile in JSON format.
    As example:
    { "remote": [
    	{ "key" : "power", 
              "code": "19082600000100260608B6044D00890089008901A20089277A08B6022D00895DA90001010201010101010202010202020202010101020101010102020201020202020304050405" },
    	{ "key" : "volmute",
              "code":  "19082600000100260608B9045100890088008901A30089277A08B9022B00895DA90001010201010101010202010202020202020101020101010101020201020202020304050405" }
    	    ]
     }
 

Get

    get <name> learncode
    after execute get function hold your remote appx. 30 cm next to the gateway and press the button you want to learn.



Set

    set <name>
    Executes a command set within the [ConfigFile]. You can learn the code with get learncode.


