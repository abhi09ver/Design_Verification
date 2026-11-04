# Logic inside the APB driver

*Chapter: APB agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the logic inside the app driver.
The starting point for us is the App Driver practice project, which we have to copy in our working area.
So let's just click copy.
Let's resize the windows a little bit to make some room.
And make sure that under Tools and simulators you unselect show output file.
After run in the driver class, we must replace this message with a task which will drive the app transfer on the bus.
That task is called drive transaction.
So let's implement it.
And let's just move this message inside this task for now.
And let's call this task instead of the message that we printed before.
We also discussed in the previous tutorial that we want to wrap this forever loop inside another task called drive transactions.
So let's do this.
And now let's call this drive transactions from the run phase.
Let's see if everything compiles.
Everything looks good.
Now let's start to drive some of those signals to build the app transfer.
And in order to do this we need to have access to the virtual interface.
But now the virtual interface in our case stays in the agent configuration class.
So let's put a pointer to this agent configuration class in our driver.
So first we declare it in the driver.
And then we will connect it in the app agent.
So let's do this.
So that's the declaration.
Now let's connect it in the app agent.
We do this in the connect phase.
Let's see if everything compiles.
It looks good.
So from this point we want to drive something on the bus.
So it's a good idea to also visualize the waveforms.
And in order to do this we need to select this open EP wave after run.
And now when we run, the waveform window will open at the end of the simulation.
So this is the waveform window.
Now we don't have any signal loaded, but we can do this by pressing this button get signals.
And then we go to duty instance.
And here we select the signals that we want to put on the waveform.
So first it will be the reset.
And you select the signal and click append selected.
And we do the same for the clock.
And now for the app signals we need p cell.
P enable.
P right.
P address.
P right.
Data.
And then the signals coming from the duty towards our agent.
So this will be p read data.
P ready.
And p slave error.
And once we are done with this we simply close this window.
You can see that the signals which should be driven by the master in our case the agent are all x p l p enabled p right.
P address and p right data.
And we can fix this by adding some initialization code in our drive transaction task.
So let's do this.
First we need to get a pointer to the virtual interface, and now that we have access to the agent config, we can simply access get VIF from this class.
So let's do this.
And before the forever loop we want to set all the signals to some default value.
Usually this will be zero.
So let's do this.
That's it.
One thing to mention here it is very important to always use non-blocking assignment when you drive some signals from the driver, because this will ensure correct sampling on the other side by the duty.
Let's see if our code had some effect.
So remember now all these signals are x.
And this code that we just added should initialize all these to some default value.
In our case zero.
So let's give it a try.
You can see now that all those signals pixel be enable have a default value equal to zero.
So this is okay.
Now let's implement the logic which drives those APB transfers.
And we can do this here inside drive transaction.
As for drive transactions we need to get the pointer to the virtual interface.
And now we can implement the code here.
Remember that we have these five elements to take into consideration the pre and post drive address write data and direction.
So first let's drive this pre drive delays.
So this is some delay starting from the moment when we get the item inside the driver until we decide to drive those signals on the interface. so it will be a simple for loop from zero to that pre-drive.
Delay.
So let's do this.
So this is the logic to wait that Pre-drive.
Delay.
Now let's begin the setup phase of our app item.
And this means that we need to assign pixel to value one p right and p address and p right data only if the access is a right.
So let's do this.
Okay so we started the setup phase.
So we are here.
Now we need to wait one clock cycle until we start driving.
Be enabled to value one.
So let's wait for one clock.
Cycle this part here and then drive be enabled to value one.
This will wait one clock cycle and then we will drive be enable.
That's it.
And now for the access phase we need to start waiting for the RTL to return period equal to one.
But starting from this clock cycle.
So we need to wait one clock cycle from the moment when we drove be enabled to one.
So from here and from here we begin to look on the be ready signal to see when the RTL makes this signal equal to one.
And at that point we know that the APB transfer ended.
So let's do this.
That's it.
At this point we know that the APB transfer Were ended.
So we need to put all those signals that we drove for this transfer back to their default value, which is usually zero.
So we can simply take this code from here and paste it here.
So at this point the transfer ended and the only thing remaining for us is to wait that post-drive delay.
And the code is quite similar to this for loop.
And the only difference is that we should replace here with the post-drive delay.
That's it.
Let's give it a try to see if our app transfers look okay.
Everything looks quite okay.
We start driving the app transfers and for all of them, the RTL returns this period at some point and also a slave error.
You can see there is this delay between two app transfers.
So maybe somewhere around here.
We have the post-drive delay, and probably from here to here we have that pre-drive delay.
But we can check this with the messages that we printed.
So for the first two accesses we can see that we have for the first one a post-drive delay of four clock cycle, and for the second one a pre-drive delay of three clock cycles.
So this means that between these two accesses we should have four plus three equal to seven clock cycles.
So let's see if we also detect this on the waveforms.
So we have 1234567 clock cycles between these two transfers.
So everything looks good.
Now one thing that we can see is that for all those accesses the duty return this slave error.
And it is right to do so because most of those accesses are to addresses which are unmapped.
So we don't have anything at those locations.
And we need to change this.
So let's try to change that.
This first access, which is driven by our simple sequence, is to the control register.
And then this read write.
So this for here and for here we can change this to go to our status register.
We can use the aligner documentation to get the addresses of those registers.
So if we scroll down to the registers chapter we can see that control is at address zero and status is at address C.
So let's change our test to access address zero for control and address C for status.
So here in our test let's constrain the simple sequence to access the control.
And we can also constrain the direction and the data.
So this will be an access to the control register.
And now for the read write sequence.
Let's constrain the address to be equal to C which corresponds to the status register.
Let's give it a try and see if in those scenarios RTL will respond with an okay response.
Okay, now for the address zero to the control register.
We have an okay response from our RTL and for the access to the status register, we can see that at address C, we can see that RTL.
First for the read part, return no error because we can read from the status register, but we cannot write to it.
So here when we do the right to the status register RTL return a slave error.
So everything looks good.
That's it for this tutorial.
Thanks for watching and see you in the next video.
Bye!
