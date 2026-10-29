# Logic to integrate the register model with the APB Bus Monitor

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to code together the logic to integrate the register model with the APB Bus Monitor.
The starting point is the "Integration with Bus Monitor - Practice" project from EDA Playground which we need to copy.
Let's resize the windows.
The first thing that we have to do is to create the file for the register adapter.
Now let's include the file and we should include the file in the cfs_apb package right at the end.
And let's look again at the reason why we should include the adapter in the APB package.
In the "UVM User Guide", in the "Transaction Adapter" chapter, there is this statement just a little bit below: "Because this transaction adapter is specific to the bus agent, not the register model, it should be provided as part of a UVM-compliant bus UVC".
So, this is why we should include it in our APB package.
Our APB agent is that UVM-compliant bus UVC.
Now let's go back to our code and define the cfs_apb_reg_adapter class.
So our adapter class extends from uvm_reg_adapter which is a virtual class.
And this virtual class has inside two pure virtual functions: bus2reg() and reg2bus().
Because those are pure virtual it means that we must implement them in our child class.
The bus2reg() will transform the information coming from the monitor, which is this bus_item, to this generic uvm_reg_bus_op which the predictor knows how to interpret.
And then the reg2bus() will do the reverse transformation, will receive this uvm_reg_bus_op, and must output an uvm_sequence_item And because in this tutorial we are doing the integration with the bus monitor, we will only implement this function and for this one we will just put here an uvm_fatal() to remind us to implement this function later on.
In this bus2reg() the information coming from the monitor comes in this bus_item but this one is of type uvm_sequence_item so we need to cast it to our cfs_apb_item_mon.
At this point after we did the casting we have in this item_mon access to all the fields from our cfs_apb_item_mon so we need to copy those fields to this uvm_reg_bus_op.
So, we have these four fields in this uvm_reg_bus_op: kind, address, data and status.
The kind holds the direction if it is write or read.
Address, data, these are self-explanatory and then the status holds the information if the access is ok or not.
So this is all we have to do in this adapter so we can move now to instantiating our predictor.
To do this we must go to the environment and in here we must declare the predictor of type uvm_reg_predictor and for that BUSTYPE parameter we must pass the cfs_apb_item_mon class type.
So let's do this.
So that's the declaration of the predictor and now in the build_phase() we must instantiate it.
That's it.
Now let's declare the connect_phase() function and in the connect_phase() we will do all the connections necessary for this predictor.
So the first thing that we have to do in this connect_phase() is to create an instance of our adapter.
Now let's connect this adapter to our predictor.
That's it.
So now our predictor knows how to transform the information from the monitor to that uvm_reg_bus_op through this adapter.
And remember that the predictor has that map field which we need to connect to our default_map from the register model.
That's it, now we only have to connect the output_port of the monitor to that bus_in from the predictor.
That's it.
So these are all the connections required by the predictor.
So the predictor receives the information from the monitor through this bus_in because we connect this to this output_port from the monitor.
Once the predictor receives the information from the monitor it will use the adapter to call that bus2reg() function in order to transform the information to something that it understands and it will use that information to send it to the register block through this map.
The next thing that we have to do is to implement the logic to reset this register block.
And as we discussed in the previous tutorial, we will use our uvm_ext_reset_handler interface class.
And we will use that uvm_ext package in our Aligner package so we will need to include it and import it.
That's it.
So now we have access to all the classes declared under the uvm_ext package in our cfs_algn package.
So let's go to the environment and mention that this should implement our UVM extension reset handler.
And because the environment implements this interface class, we also need to declare that reset handler function.
And let's take its signature from our UVM extension package.
So it's this one from here.
And let's add it in our environment.
And in here we will call the handle_reset() of the model.
Currently that is not implemented but we can already add the code.
That's it.
Now the environment should be the main class which looks for the reset and then triggers this handle_reset().
So let's implement something similar to what we did in the agent.
So in the run_phase() we will have a forever loop which will wait for the reset to start, will call this handle_reset() and then wait for the reset to end.
So let's do this.
Let's first declare those two tasks: wait_reset_start() and wait_reset_end() and then we will implement the run_phase(). and then we will implement the run_phase().
And we can simply call the wait_reset_start() from our APB agent because it will be the same logic.
That's it.
Now let's do something similar for wait_reset_end().
And now let's implement the run_phase().
As you can see the logic is pretty simple.
It's quite similar to what we did in the agent.
And now let's implement the handle_reset() in our model.
So we need to take this implements uvm_ext_reset_handler and we should put it here.
And let's also take the signature of the handle_reset() function and call the reset() function of the register block.
That's it.
As I told you the logic is pretty simple.
In the handle_reset() function of the model we call the reset() function of the register block and in the environment in the run_phase() we call the handle_reset() function which calls the handle_reset() function of the model.
And there is one mistake here which we can fix it now.
The run_phase() also has as an argument the phase so let's declare it here.
Now let's switch the test that we are running an we can do this in the "Run Options" here in the UVM_TESTNAME.
Currently we have that random test an we want to put that register access test.
And let's go to our register access test and let's remove all the code from here and we can add some simple accesses to the registers just to be able to see them easily.
So first let's add a write to the Control register.
That's it, so we are doing a write access to the Control register, so address 0x0 and we are writing the SIZE and the OFFSET both with value 0x2.
So let's select "Open EPWave after run" and try to see how this will look like on the waveforms and in the log.
That's it, the simulation finished and let's add the signals from the APB interface.
So we have this write access with data 0x202 and the RTL returns an OK response.
And let's look on the log.
And from the log we get our messages from the driver and from the monitor but we need some kind of proof that our register model is working.
And to achieve this we can enable some of the messages from our UVM register model.
And we can do this here in the "Run Options" using the +uvm_set_verbosity.
So that's the syntax for this +uvm_set_verbosity.
This allows us to enable all the messages from all the components.
This is what this * means.
We can enable all the messages with this ID, or tag, REG_PREDICT, and we can put the verbosity to high and here we specify the phase in which we want this to be implemented so in the "run" phase.
Now let's try to run again to see if we get any messages from our UVM register block.
That's it.
The simulation finished and now let's look in the log to see if we get any new messages.
And we get this new message from the predictor saying that there is an observed write transaction to register Control with value 0x202.
So this is exactly what we want it to do.
And it also says that it updated the register to value 0x202.
Now let's try to change a little bit our environment to see if we can get an error from our UVM register model to see how such an error will look like.
And to achieve this we can do something like this.
We can add a read just before this write, so let's put it here.
This will first read the Control register and to trigger an error we can actually change what we declared as the reset value of the fields from the cfs_algn_reg_control.
So if we go here, let's change the reset value of the SIZE to let's say to be 0x0.
And now because we changed the reset value to 0x0 instead of 0x1 and in our test we first read the register, so this read should return the reset value.
RTL will still return 0x1 as the correct value, but we will have value 0x0.
So let's see if this will trigger an error and if this happens, how that error is reported.
The simulation finished and we can already see from the waveforms that it stopped at this read.
So this is a good sign and let's also look in the log.
So we have our error triggered and it is saying that the register Control was read and the value read from the DUT is this 0x1.
Which is correct actually, but in our mirrored value we have 0x0.
So this is how an error looks like when there is a mismatch.
So now let's fix our code.
Let's put here the correct reset value which is 0x1 and then in the test let's move this read after our write to make sure that the mirrored values are updated correctly during this write, and then in the read we are reading those values.
That's it.
So on the waveforms we are seeing the write and then the read.
So the write with 0x202 and then the read returns also 0x202 and in the log we should get no errors from our register model so this one looks ok.
And if we look on the messages there is this first message from the predictor saying that there is a write transaction observed with value 0x202 and then there is this other message from the predictor observed read with value 0x202.
So everything looks good.
Now let's try one more access and I will show you in this access why we need to create a specific predictor for us.
So in the write access let's change this to something which is illegal.
So let's put for the SIZE value 0x0.
So now we are trying to write the SIZE with value 0x0 and the OFFSET with value 0x2, but writing SIZE with value 0x0 is illegal and the RTL should return an error.
So this access should not be written inside the RTL and then when the read comes actually the expected value for the read should still be the reset value SIZE = 0x1 and OFFSET = 0x0 because this one returns an error.
And let's try to run to see exactly what is happening.
The simulation finished and you can see that it stopped at this read.
So if we look on the log, we should see here an error.
So we have this error here and let's see what the log is saying.
So during the first access, which was the write, the predictor says that there is an observed write transaction with value 0x200 and it says that it updated the value of the register.
And then when the read comes, the RTL returns the value 0x1, but our environment expects this 0x200.
So let's look on the waveforms.
During this write, the RTL returned this "slave error" because it recognized that writing with value 0x0 for the SIZE is illegal.
However, our register model gets updated and this is because the default predictor does not look to see if the access is with error or not, it will do the update no matter what.
So, this is something that we will fix in the next tutorial when we will extend the uvm_reg_predictor class and we will create our own predictor which will filter all the accesses with errors and beside that it will also check the response from the RTL so we will check if the access should return an error or not.
But as you can see we need to extend our default predictor in order to handle such cases.
That's it for this tutorial, so we managed to connect correctly our register block to the monitor from our APB agent and in the next tutorials we will talk about how we can extend the predictor to resolve our cases for the accesses with errors on the APB bus.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
