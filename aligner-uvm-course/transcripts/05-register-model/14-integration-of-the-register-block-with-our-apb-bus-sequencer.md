# Integration of the register block with our APB bus sequencer

*Chapter: Register model (RAL) · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to code together the integration of the register block with our APB bus sequencer.
The starting point is the project "Integration with Bus Sequencer" from EDA Playground which we need to copy.
And now let's resize the windows.
The first thing that we have to do is to go to the adapter and implement the function reg2bus().
Remember that we have to copy the information from the uvm_reg_bus_op to our cfs_apb_item_drv.
So let's do this.
That's it.
So here I'm creating this instance of item drive and then I'm randomizing it and in the constraints I'm copying the values from the uvm_reg_bus_op: kind, data and address to the fields from our item.
And then I'm simply returning this item.
Now there is one more thing to do here in the adapter in the function bus2reg().
We also have to copy the fields from the item drive just like we did for the item mon.
And this is because in the background the register block will call this function bus2reg() also for this item cfs_apb_item_drv.
So let's implement here a similar code like this one.
That's it, so I'm copying direction, address and data from cfs_apb_item_drv to kind, address and data from uvm_reg_bus_op.
And for status, because we don't have access to the status in item drive, I simply put it to UVM_IS_OK.
Now the only remaining thing in order to connect the register block to the sequencer is to set the pointer to the sequencer and to the adapter.
And remember from the previous tutorial that we had to use that function set_sequencer() of the map.
And we can do this here in the connect_phase() of the environment.
So let's do this.
That's it.
So I'm calling here the function set_sequencer() of the default_map and I'm passing the pointers to the sequencer and to the adapter.
So that's all we have to do in order to take advantage now of those tasks from the uvm_reg class write(), read() and update().
Now let's go to our register access test and in here we can replace these lines with a simple call to that write() task.
So let's do this.
That's it.
So this write() task also has as an output argument this status.
This is why I had to declare it here.
And the second argument of this write() task is the data which we want to write.
Now let's also enable this "Open EPWave after run" to see the waveforms with our access to the Control register.
The simulation finished and now let's add on the waveforms the APB signals.
So it looks like everything is working.
Here is our access to the Control register so address 0 with data 0x202.
And now let's get back to our code and let's remove these lines.
And let's try to replace this call to the write() task with a call to the update() task.
And the advantage of using update() is that we can set the desired values of the register fields using that set() function of the uvm_reg_field class.
And in this way we no longer have to care about the position of the fields that we want to write.
So let's try to do this.
That's it, so I replace the call to the write() task with these lines in which I'm setting the desired values for SIZE and OFFSET and then I'm simply calling the update() task.
So now when we run we should get the same effect on the waveforms.
The simulation finished and as you can see on the waveforms we still got the same access with value 0x202 to the Control register.
And now let's also try that read() task so we can replace these lines of code with a call to the read() task.
So let's do this.
That's it, so the read() task has two output arguments, status and data, so this is why I had to also pass here the data declared here.
So let's give it a try and see if we can get on the waveforms also the read access.
The simulation finished and as you can see we also get our read access on the waveforms with the correct data 0x202.
Now let's try one more thing, instead of this update() let's try to randomize our Control register and then do an update() to see what values we get on the bus.
That's it, so I'm randomizing the Control register and then I'm doing an update().
So let's see now what we get on the waveforms.
The simulation finished and we get some random data for the SIZE and OFFSET.
You can see that the SIZE is equal to 6 which is illegal and this is why the RTL returns an error here.
And when we read the register back we get value 1, the reset value of the Control register because this write did not work.
Keep in mind that you might not get the same value as I did in my simulation, as the randomization depends on exactly how you are writing the code, the version of the simulator, and so on.
Let's do one more thing.
Let's try to wrap these accesses to the Control register into a sequence which is extending from that uvm_reg_sequence and we can name that sequence something like reg_config which we will use in the future to configure properly the RTL.
So first let's create the file.
And now let's include this file in our Aligner package.
That's it and now let's declare our cfs_algn_seq_reg_config class.
That's it.
Now let's copy from our test the accesses to the registers.
And here we don't have access to the environment so we have to declare a pointer to the register block.
So let's do this.
Now let's make use of this pointer.
We can replace env.model.reg_block with this reg_block.
Now one more thing that we have to do is to declare the status and the data fields here.
So let's take them from our register access test.
Now our sequence is complete and we can make use of it in our test.
So here we can replace these lines of code with our sequence.
That's it, so I'm creating a new instance of the sequence, I'm connecting the pointer to the register block and then I'm starting the sequence using the sequencer from the default_map.
So in the uvm_reg_map we also have this getter for the sequencer.
So now let's give it a try and see if we get the same waveforms as before.
The simulation finished and as you can see we have exactly the same accesses, the write with the illegal combination for SIZE and OFFSET and then the read.
So now it's time to write the constraints in the Control register in order to get legal values every time we are randomizing the Control register.
So let's go to our register Control class and here we have to write those two constraints for legal SIZE and for legal combination between SIZE and OFFSET.
So let's first write the constraint for the SIZE.
That's it.
So remember that in the constraints we have to use the "value" property from the uvm_reg_field class.
So for the SIZE this one should be different than 0.
Now for the legal combination between SIZE and OFFSET we also need here the information regarding the aligner data width.
So let's add that information field as a local field and we will implement getter and setter and then we can write the constraint.
Let's assign some default value to this in the constructor.
And now let's implement the getter and the setter.
And remember that for the aligner data width, we have some limitations on the values that it can take.
So it should have a minimum value of 8 and it should be a power of 2.
And we already implemented these checks in the setter in the aligner environment config.
So we can take these checks from here and put them in our register Control.
That's it.
Now we also have here in the register Control these checks.
Now let's declare the constraint for the legal combination between SIZE and OFFSET.
That's it.
So we applied that formula from the Aligner specifications, aligner data width in bytes, plus OFFSET modulo SIZE it should be equal to zero.
Now let's assign the correct value for the ALGN_DATA_WIDTH and we can do this in our model.
Here, in order to have access to the aligner data width we need a pointer to the environment config class.
So we can go to the environment and take this line of code.
And place it here and in the end_of_elaboration_phase() we can assign here the correct value to that ALGN_DATA_WIDTH.
That's it and now in the environment let's connect this pointer to the environment config.
Here, just like we did in the predictor, let's do the same thing for the model.
Now let's try to run to see if now we are getting legal values when we are randomizing the Control register.
That's it, the simulation finished and it looks like the randomization of the Control register indeed produced legal values for the SIZE and OFFSET as the RTL did not return any error here.
And you might get here different values than me depending on when you are running this code as the version of the simulator might be updated, but in my case I obtain the random value for SIZE equal to 5 and the random value for OFFSET equal to 1.
And this is inline with the constraint that we applied.
So the aligner data width is 4 so 4 plus 1 equals 5 and the SIZE is 5 so 5 modulo 5 will be 0.
But you might have noticed that there is something wrong here because the SIZE was generated with value 5 and it is impossible to send 5 bytes on a bus which only has 4 bytes in width.
So maybe for this case the RTL should have returned here an APB slave error.
And you can see that the RTL accepted this access.
The return value for the read access is also 0x105 and it did not return an error.
So there is something fishy here.
So let's try to send some data on the RX interface and see how that data is outputted.
And for this let's go to our random test and here we should take these lines of code which start our TX agent.
So this is a fork join_none so it will start in the background.
And then let's take these lines of code and change it a little bit.
So after we configure the RTL, let's send some traffic on the RX interface and let's send two accesses.
And let's constrain the size of these two accesses to send the maximum 4 bytes.
That's it.
So now in the test I'm starting the response sequence on the MD TX agent and after the random configuration of the Control register I'm starting two sequences on the MD RX agent and both are sending the maximum number of bytes which is 4.
So let's see how our Aligner RTL behaves in this scenario as it has in that SIZE field now set value 5.
Our simulation finished, the waveforms did not open and this is because we had an error in our simulation and now let's look in the log to see the error.
And here you can see that we have an error from our MD TX interface saying that the size plus offset is greater than the data width.
So we had an assertion in this file in cfs_md_if.sv and let's go there at line 196.
So is this assertion here which is triggered when on that interface we detect that the size plus the offset is bigger than the data width as it is not physically possible to output these many bytes.
But to see the waveforms let's comment this assertion for the moment and try to rerun and see what the RTL is outputting.
And now let's add the signals from the MD RX interface and now from the TX interface and let's zoom.
And you can see on the RX interface we are sending two transfers both with size 4 and offset 0.
And then on the TX interface the RTL tries to send an access with size 5 which makes no sense as it only has 4 bytes available in the data bus.
So this is actually an RTL bug and it is not only just an RTL bug, but it is also a bug in the Aligner specifications.
So this is our current version of the "Aligner Datasheet" and if we go to the chapter: "Flow Control" / "RX Controller" we have here that formula that we also added in the constraints.
But as you can see this formula is not enough.
We also need to constrain the fact that the offset plus size cannot be bigger than the aligner data width in bytes.
So, finding an RTL issue like this one and also a spec issue while you are developing the environment it's quite common as both the concept engineer and the design engineer might have overlooked an error scenario like in our case.
And we actually caught this bug now because if you remember when we developed the MD protocol, we added this assertion because it made sense for us then, but this assertion we implemented not because we had some statement in the spec, we implemented just because it made sense at that point in time.
But definitely this is a bug in the spec and also in the RTL.
And for the spec I will attach to this tutorial a new version of the spec "Aligner Datasheet" version 1.1 and here in the "RX Controller" chapter I added this extra constraint size plus offset must not be greater than the aligner data width in bytes.
So you will find this document attached to this tutorial.
Now let's go to our RTL this time and fix this problem in the code and we can fix this problem in this module cfs_regs.
Let's make this window a little bit bigger.
If we scroll down here starting from line 198 there is some code which is verifying the access to the Control register and here there is a condition to trigger an APB error if the aligner data width plus the OFSSET that we want to write modulo SIZE is not equal to zero.
So let's add a similar code for our new formula which is the OFFSET that we want to write plus the SIZE if it is greater than the aligner data width then we trigger an error.
So in a real project fixing the RTL code is the job of the designer of course but in our case we will do also this task here and starting with the next practice project you will get the updated RTL with this issue fixed.
So now the RTL will return an error if such an access happens.
And now let's try to run to see if we get an error from the RTL.
And as you can see, the simulation finished at the end of the write access to the Control register.
Here, the RTL indeed returned an error, but let's see why the simulation finished here.
And the simulation finished because we triggered that error from the predictor which is checking the response from the RTL.
And in this case, because we did not implemented this extra condition in the predictor, our predictor says that it is expecting an OK response as everything looks OK but the RTL returned an error.
So what we need to do is to add in predictor that extra error scenario.
Here we should add that condition in which OFFSET plus SIZE should not be bigger than the aligner data width.
That's it, so now we are also considering this error scenario: OFFSET plus SIZE bigger than aligner data with in bytes.
So let's now give it a try.
The simulation finished and we can see that this access with the illegal combination of SIZE and OFFSET is rejected by the RTL with this pslverr.
And when we are sending these two accesses on the RX MD interface, these values are starting to get outputted on the TX interface.
And also let's look in the log to see if we have any error and we don't.
Now the only remaining thing is to add that extra constraint in our Control register.
And here we can also add OFFSET plus SIZE to be less than or equal to aligner data width.
That's it.
Now let's try to see if this constraint is working.
The simulation finished and it looks like our constraint is working as it is generated values 1 and 1 for the SIZE and OFFSET and we can also see that once we send the data on the MD RX interface the RTL started to output data on the TX interface using as size and offset the new values 1 and 1.
These are the ones that we configured here.
So that's it for this tutorial.
We managed to connect our register block to the sequencer, we managed to implement correctly our constraints in the Control register, and we also found our first bug in this RTL.
And remember that it is quite common to find issues in the RTL or in the specifications or in both while you are developing the verification environment.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
