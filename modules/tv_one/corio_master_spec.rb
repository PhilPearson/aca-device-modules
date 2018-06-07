Orchestrator::Testing.mock_device 'TvOne::CorioMaster',
                                  settings: {
                                      username: 'admin',
                                      password: 'adminpw'
                                  } do
    transmit <<~INIT
        // ===================\r
        //  CORIOmaster - CORIOmax\r
        // ===================\r
        // Command Interface Ready\r
        Please login. Use 'login(username,password)'\r
    INIT

    should_send "login(admin,adminpw)\r\n"
    responds "!Info : User admin Logged In\r\n"
    expect(status[:connected]).to be(true)

    should_send "CORIOmax.Serial_Number\r\n"
    responds <<~RX
        CORIOmax.Serial_Number = 2218031005149\r
        !Done CORIOmax.Serial_Number\r
    RX
    expect(status[:serial_number]).to be(2218031005149)

    should_send "CORIOmax.Software_Version\r\n"
    responds <<~RX
        CORIOmax.Software_Version = V1.30701.P4 Master\r
        !Done CORIOmax.Software_Version\r
    RX
    expect(status[:firmware]).to eq('V1.30701.P4 Master')

    # Fudge the initial status query - check this latest in the tests
    should_send "Preset.Take\r\n"
    responds <<~RX
        Preset.Take = 1\r
        !Done Preset.Take\r
    RX
    should_send "Windows\r\n"
    responds <<~RX
        !Done Windows\r
    RX
    should_send "Canvases\r\n"
    responds <<~RX
        !Done Canvases\r
    RX
    should_send "Layouts\r\n"
    responds <<~RX
        !Done Layouts\r
    RX

    exec(:exec, 'System.Reset')
        .should_send("System.Reset()\r\n")
        .responds <<~RX
            !Info: Rebooting...\r
        RX
    expect(result).to be(:success)

    exec(:set, 'Window1.Input', 'Slot3.In1')
        .should_send("Window1.Input = Slot3.In1\r\n")
        .responds <<~RX
            Window1.Input = Slot3.In1\r
            !Done Window1.Input\r
        RX
    expect(result).to be(:success)

    exec(:query, 'Window1.Input', expose_as: :status_var_test)
        .should_send("Window1.Input\r\n")
        .responds <<~RX
            Window1.Input = Slot3.In1\r
            !Done Window1.Input\r
        RX
    expect(result).to be(:success)
    expect(status[:status_var_test]).to eq('Slot3.In1')

    exec(:deep_query, 'Windows')
        .should_send("Windows\r\n")
        .responds(
            <<~RX
                Windows.Window1 = <...>\r
                Windows.Window2 = <...>\r
                !Done Windows\r
            RX
        )
        .should_send("window1\r\n")
        .responds(
            <<~RX
                Window1.FullName = Window1\r
                Window1.Status = FREE\r
                Window1.Alias = NULL\r
                Window1.Input = Slot3.In1\r
                Window1.Canvas = Canvas1\r
                Window1.CanWidth = 1280\r
                Window1.CanHeight = 720\r
                Window1.CanXCentre = 689\r
                Window1.CanYCentre = 0\r
                Window1.Zorder = 1\r
                Window1.RotateDeg = 0\r
                Window1.WDP = 0\r
                Window1.WDPQ = 2048\r
                Window1.BdrPixWidth = 1\r
                Window1.BdrRGB = 0\r
                Window1.HFlip = Off\r
                Window1.VFlip = Off\r
                Window1.FTB = 0\r
                Window1.SCFTB = Off\r
                Window1.SCHShrink = Off\r
                Window1.SCVShrink = Off\r
                Window1.SCSpin = 0\r
                Window1.AccountForBezel = No\r
                Window1.PhysicalCenterX = 547800\r
                Window1.PhysicalCenterY = 0\r
                Window1.PhysicalWidth = 1018300\r
                Window1.PhysicalHeight = 572800\r
                !Done Window1\r
            RX
        )
        .should_send("window2\r\n")
        .responds(
            <<~RX
                Window2.FullName = Window2\r
                Window2.Status = FREE\r
                Window2.Alias = NULL\r
                Window2.Input = Slot3.In2\r
                Window2.Canvas = Canvas1\r
                Window2.CanWidth = 1280\r
                Window2.CanHeight = 720\r
                Window2.CanXCentre = 689\r
                Window2.CanYCentre = 0\r
                Window2.Zorder = 1\r
                Window2.RotateDeg = 0\r
                Window2.WDP = 0\r
                Window2.WDPQ = 2048\r
                Window2.BdrPixWidth = 1\r
                Window2.BdrRGB = 0\r
                Window2.HFlip = Off\r
                Window2.VFlip = Off\r
                Window2.FTB = 0\r
                Window2.SCFTB = Off\r
                Window2.SCHShrink = Off\r
                Window2.SCVShrink = Off\r
                Window2.SCSpin = 0\r
                Window2.AccountForBezel = No\r
                Window2.PhysicalCenterX = 547800\r
                Window2.PhysicalCenterY = 0\r
                Window2.PhysicalWidth = 1018300\r
                Window2.PhysicalHeight = 572800\r
                !Done Window2\r
            RX
        )

    exec(:preset, 1)
        .should_send("Preset.Take = 1\r\n")
        .responds(
            <<~RX
                Preset.Take = 1\r
                !Done Preset.Take\r
            RX
        )
        .should_send("Preset.Take\r\n") # Mock the status query
        .responds(
            <<~RX
                Preset.Take = 1\r
                !Done Preset.Take\r
            RX
        )
        .should_send("Windows\r\n")
        .responds("!Done Windows\r\n")
        .should_send("Canvases\r\n")
        .responds("!Done Canvases\r\n")
        .should_send("Layouts\r\n")
        .responds("!Done Layouts\r\n")
    wait_tick
    expect(status[:preset]).to be(1)
end
