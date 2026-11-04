# MD protocol checks

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to implement together the MD protocol checks.
If you remember from the previous tutorial, these are the 16 rules that we identified as the rules governing the MD protocol.
And in this tutorial we are going to implement all of these together.
So let's get started.
The starting point is the MD protocol checks practice projects which we need to copy.
We should resize the windows.
And select open EP Wave after run and go to the MD interface.
In this file, to make things a little bit easier, I already added as comments 15 of the rules that we have to implement here in the interface.
So let's get started with the first rule.
Data width must be a power of two.
In the previous tutorial we discussed that the checks for the data width will not be simple assertions because there is no point to verify.
For example, the data width on every positive edge of the clock data.
Width is a parameter, so this is static throughout the simulation.
So we want our check for the data width to be executed as early as possible.
And for this the first step that we can do is to implement the check in an initial begin block.
So let's do this.
We know that the code in an initial begin block is executed at the beginning of a simulation.
So we can place the code to check the data width here.
And because the value of the data width influence everything else in our agent, we don't want to enable or disable the check based on hash checks.
We want the check on the data width to be executed every time, and to verify that the data width is a power of two.
We can use a systemverilog built in function called count once.
Remember that a number is a power of two if its binary representation has only one bit equal to one, and the rest are zero.
So we can take advantage of this.
That's it.
Let's save and see if our code compiles and runs correctly.
Our simulation finished, we have no compilation error and our check was not triggered.
So now let's try to change the code in order to trigger this error.
So the only thing that we have to do is to try to change the data with value.
So let's remember how the data is passed.
And this is done in the test bench.
And we have here our two instances of the MD interface.
And we have this aligner data width parameter here.
And unfortunately here we have a problem.
We use this local parameter aligner data with equal to 32.
But if you remember in the test defines we already had a defined there with the value 32.
So if we go here we have this one.
So this one we need to use it here in our test bench in order to only change in one place the value of the data width.
Now let's try to change the value of this defined to value 33.
And this should trigger our error.
And we actually have a compilation issue.
And let's fix this.
So the first error is reported in the MD agent at line 57 where the connection of the agent config is performed.
So let's go there and see what exactly is the problem here in the agent config at line 57, we are connecting the pointer of the agent config to the one in the monitor, and let's see exactly if we made a mistake when we declared the agent config.
So here the agent config is of type cfs MD agent config with the correct parameter data width.
So this one looks okay.
And now let's go to the monitor and see how we declared this agent config here in the monitor.
I actually forgot to use the parameter when I declared the agent config, so this one will have the default value of the data with equal to 32, but from the testbench these data width is passed as value 33.
So this is why it is complaining about this connection.
It is trying to connect an agent config declared as a class with parameter data width equal to 33 to the same class, but with a parameter equal to 32.
So we need to fix this.
We need to add the data width parameter to this class here.
That's it.
Now let's save and try to run again.
We still have a compilation issue and let's see exactly what the problem is now.
Now the problem is in the agent at line 62.
So let's see exactly what it is there.
At 62 we are trying to do the same connection but to the agent config from the driver.
So let's see how we declared the agent config inside the driver.
You see here again I forgot to put the data with as a parameter, but unfortunately here the driver don't have the data with as a parameter, so we need to add it.
And this is a big problem when you are coding a lot using classes with parameters, you have to be very, very careful to pass all the parameters correctly.
But now let's try to fix this problem.
Let's add data width as a parameter to this cfs MD driver and then use that parameter also here when we declared the type of the agent config.
Now we also have to fix in the agent where we created the instance of this driver.
And now let's add the data width parameter in the driver slave and in the driver master.
That's it in the driver slave.
And let's copy this code also in driver master.
And now in the agent master and in the agent slave where we did the override for the driver.
We also need to use there the data width.
So for the slave it should be here.
And for the master it should be here.
Okay.
Now let's save and see if our code compiles and our error for the data with is triggered.
Okay.
Our code compiled and run correctly.
And we also have an error.
And let's see if our error was reported correctly in the beginning of the simulation.
So we have our error here.
Data width is not a power of two.
And then we printed the value in binary.
Hex and dec.
So it is reported correctly.
But our simulation did not finished right away when this code was executed.
And one thing that we can do in order to stop the simulation right away.
Actually, when the interface gets instantiated by moving this code outside the initial block, and in this way the check will be done exactly when the interface gets instantiated.
So let's try to run this code outside the initial block.
And we actually have a compilation error.
And let's see exactly what the error message says.
So the error message is this one.
And it is saying that the system task or function count one is used in a currently unsupported context in this constant expression.
So it is referring to this code here.
It basically says that the simulator from cadence does not accept the usage of count ones in this constant expression here, but let's see how other simulators behave in this scenario.
So first let's try the mentor simulator.
But before we go there, let's take this run.
Options we use for cadence with this UVM test name in which we specify the test, and also the last one regarding the UVM max with count.
Copy this one and then change to the Mentor Cuesta simulator and add those run options here, because those options are related to UVM.
Also, the mentor simulator will support them.
So let's save and try to run to see if the simulator from mentor can support this count ones usage so it looks like the mentor simulator run.
It did not complain that this is a compilation issue, but when we look at the message, we get this weird message here.
And one solution to this is to actually get rid of the usage of s format f function inside the error, and let's see if this change will actually work.
And we get the simulator to print the correct message.
The simulation ended.
And let's look at the error message.
And you can see now that we have the correct error message from mentor.
The data width is not a power of two.
And then the printed value in these three representations.
So you can see there are differences between the simulators even though all the simulators are running the same language Systemverilog but different syntax in the language might be supported or not by different simulators.
And let's see if our entire test runs correctly on the mentor simulator if we fix the value of the data width.
So let's put here 32, which is a correct value.
It's a power of two.
And let's see if this simulator is running okay.
Our test.
So the simulation finished.
And if we scroll up in the log we can see that we have our messages from the monitor and from the driver with all the information that we wanted to drive.
So this one looks okay.
Now let's try to change back here the value of the data with to 33 and switch to the last simulator to this Synopsys VCs simulator, and also put here the run options which we used for the UVM mux quit count and also for the test name.
And let's run the synopsis simulator now and see how this one performs.
Okay, we have a compilation issue and let's see why this one is complaining.
If we look at the error, it is saying that using elaboration system tasks require the option.
This one.
So let's add this option here in the compile options.
And let's try again.
So you can see that with a synopsis simulator.
Just by adding that option in the compile options we get the simulator to trigger correctly.
Our error data width is not a power of two.
But now let's fix this back to 32 and let's see if the test runs correctly on synopsis simulator.
The simulation finished and it looked like we have an error.
And let's see exactly what this error says.
It is complaining that in the MD sequence.
Simple master.
At line 17 we are using this function Getdata with.
And.
Let's go to this file and see exactly what we wrote there.
So here at line 17 we had a constraint in which we used this function.
And it turns out that the synopsis simulator does not like to use function inside constraints.
And we can fix this problem just by declaring the data width as a local variable here, which we initialize in the randomize function, and then use that field here.
So let's do this.
That's it.
So we use this field here to get the value of the data within the randomize function.
And remember the randomize function is called before randomization.
So before this constrain is taking into account.
Now let's see if the simulator from synopsis will compile and run correctly our test.
The simulation finished.
And if we scroll in the log we can see that also our messages got printed from the monitor from the driver and we don't have any error.
So it looks like our testbench is also working now with the synopsis simulator.
But remember that we still have an issue with the cadence simulator when we run our code.
It does not like that we are using this count once here.
So the solution here is to find a different way to determine if the data width is a power of two.
So we cannot use this function.
We need to come up with a different function.
So our goal is to determine if the logarithm in base two of data width is an integer.
And we can do this in the code by getting the real value out of this logarithm of data width, and subtract the rounded value of the same number, and this is the sign for the rounding up.
So the ceiling value and if the real value minus the rounded value is equal to zero, then this means that the real value is an integer.
And now the problem is how to extract this logarithm of data with in base two.
And we can see what functions are available for us in Systemverilog by opening the SRV documentation.
And if we go through the chapters, there is this chapter 20 the utility system tasks and system functions. 20.8 Math functions.
And here we have this real math functions.
And this table lists all the functions which return a real values.
And you can see that we have the natural logarithm or decimal logarithm.
But we don't have a logarithm in base two.
But that's no problem because we can compute logarithm in base two if we have this function.
So the formula to transform from one base to another is this one logarithm.
In base two of data with, it's equal to logarithm in base ten of data with divided by logarithm in base ten of two.
So because in systemverilog we have this function logarithm in base ten.
We can use this formula here to get this value.
And for the ceiling value, we already have a function in Systemverilog.
If we go back to the documentation and we scroll up a bit, we have in this chapter integer math function, we have this ceil log two, which is exactly what we need.
It will return the ceiling of log base two.
So the formula that we can use in our code is this one logarithm in base ten of data width divided by logarithm base ten of two.
In order to get this value here minus ceiling of log two of data width.
If it is different than zero, then we trigger an error.
So let's also code this in our interface.
That's it.
Let's see if the cadence simulator accepts this log syntax.
So the simulation finished We don't have any compilation error.
Everything ran okay.
And now let's try to trigger our error using the cadence simulator.
So let's change this.
Define to value 33 and we get the error.
Also from the cadence simulator.
It is saying that the data width is not a power of two.
So it is detecting correctly our error scenario.
But now that we change the error message to use this log10 function and c log2, let's see if other simulators, the mentor and the synopsis will accept this syntax.
So first let's try with mentor.
And remember that in this scenario we have the data with equal to 33.
So the error should be triggered okay.
We have the error reported by the mentor simulator.
And now let's see the synopsis simulator.
And also synopsis Simulator is reporting correctly the error.
This was a very good example to show what kind of problems you might encounter when you change the simulator used for running your code, and depending on when you are taking this tutorial, there might be updates to the tools used by the EDA playground platform, so that the initial code that we wrote is already supported by all three major simulators, but in general, making sure that the code you are developing is running correctly on all the major simulators is something that you should take into account, especially when you are developing commercial verification components.
But now that we saw what it takes to make the code run correctly on all these three simulators, let's switch back to cadence and develop the rest of the assertions that we have to implement here.
So let's implement the check for the data width to have a minimum value of eight.
And this one will be in the same constant context as this one from above.
That's it.
Let's see if our code runs correctly when we first set the data width to value 32.
So in this scenario, none of our checks should be triggered and we have a compilation issue.
Let's fix it.
I forgot here to put a semicolon.
And I also have here a typo.
Let's save and try again okay the simulation finished.
We have no compilation issue and the simulation run correctly.
And now let's try to trigger our error by setting the data with equal to four.
So this is a power of two number.
So the first error will not be triggered.
But the second one should because it is smaller than eight okay.
Our error was triggered.
Data width must be bigger or equal than eight.
So our check worked okay let's fix this value and move forward.
Now let's implement rule number three.
Once valid becomes high, it must stay high until ready becomes high.
So for this let's implement a property and then an assert property.
That's it.
So our assertion will check that when valid has a falling edge.
Then in the previous clock cycle ready was one.
So let's save and run this code to see if everything compiles correctly.
Everything ran correctly.
We did not get any compilation or simulation error.
And now let's try to change our code a little bit to try to trigger this error.
So first let's select open EP wave after run and run again to add some signals on the waveforms.
Okay now let's add the ADX and takes interfaces.
That's it.
And if we look on the waveforms, our error is triggered.
If valid becomes zero without having this ready signal high.
But in this test, the MD transactions from the ADCs interface all have a minimum length.
And this is because the RTL is able to take this incoming data immediately.
And let's try to change our test in order to make the MD transactions longer.
But in order to know how to change the test, we need to remember something about our aligner.
If we scroll in the aligner datasheet to the figure one here, we can notice that the incoming data on the Eric's interface goes into an Eric's Fifo.
And as long as this Eric's Fifo is not full, then this Eric's controller will accept right away any incoming data.
So the key to get longer transactions on the MDX interface is to try to send as many transactions as possible in order to fill this Fifo.
So let's try to do this.
Let's change our random test in order to send transactions with the maximum number of bytes for and with no delay between transactions.
So let's go to our test random and apply some constraints to the simple master sequence here.
First, we want to send transactions with the maximum number of data bytes.
Next, we want to limit the pre and post drive delay to value zero, so the items will be as close as possible.
That's it.
And now let's try to fill that edit Fifo by sending let's say 11 items.
That's it.
Let's save and run again our simulation to see if we manage to fill the Fifo.
That's it.
You can see now that our RTL at some point lowers the air ready to value zero because it cannot receive at this point any new information on the air interface.
And we can also see this by adding on the waveforms a signal from the air Fifo, which will tell us what is the fill level on its push interface, and we can get this information from this signal called push Fifo level inside the Fifo submodule.
And let's zoom a little bit here.
And you can see that once the ethics interface starts to push information inside our aligner, the fill level of the ethics Fifo starts to go up 1234578.
And because the maximum level is eight at this point our internal ethics Fifo became full.
So the ethics ready goes low.
And if you notice this clock cycles in which the fill level stays to two and then again to two and the same here for five and five.
This is because in these moments during the simulation, if we look on the aligner documentation again at this moment, the controller here inside managed to pull up some information from the Fifo in order to align it.
And this is why the field level of this Fifo, even though we pushed data on the ADX interface here, managed to stay constant at two or here at five.
But in the end, because we pushed a lot of data on this ADX interface, we managed to fill this Fifo and get this error signal equal to zero here.
So this is the scenario that we need in order to test our assertion regarding the ADX.
Valid to stay high until ready is high.
So let's change our code to see if we lower the ADX valid here.
If our assertion gets triggered.
And in order to do this we need to change the MD driver master.
So this is the part where our transaction starts, and then we wait for the ready to become high.
So at this point we can actually drive valid equal to zero right after this positive edge of the clock.
And let's see if our assertion gets triggered.
Our simulation finished and we actually got this message execution interrupted or reached maximum runtime.
And this is because our driving got stuck because we drove here valid equal to zero.
And if we scroll up a little bit, we should also see our assertion reported here at time 215.
It says that valid signal did not stay high until ready became high.
And if we look on the waveforms and remember that in this error scenario.
EDA playground does not generate new waveforms.
So these are the old waveforms here at this time 215 we lowered in the previous clock cycle valid signal here.
So here it was zero.
So it had a falling age without ready.
So our assertion was reported correctly.
And now let's fix our code here and move forward to the next assertion that we need to implement data is valid while valid is high.
So let's implement this assertion.
That's it.
So the assertion is quite similar to what we did for the APB.
And we actually have a few more other assertions with this logic.
So we can copy this assertion and adapt it for rule six.
Offset is valid while valid is high.
So let's also implement that assertion here and change data to offset.
So this is rule six.
And also we can implement the same way rule eight size is valid while valid is high.
And also rule 11 is the same logic.
Error is valid only when both valid and ready are high.
So let's also implement this one here.
But for error.
Let's not forget to also verify here.
Ready?
And we can actually do the same thing for a ready signal.
But for this one we only ensure that it is valid while valid is high.
And finally, on the same logic we can implement a rule 13 valid cannot have an unknown value.
And I actually did a mistake I should check is unknown equal to zero.
So let's fix this in all the assertions.
And for here, let's also not forget to put valid here.
That's it.
Let's see if our code compiles and runs correctly.
We have a compilation issue.
Let's fix it.
Here I should specify the property.
And also here.
That's it.
Let's see if our code compiles.
So everything run correctly.
We don't get any error in our log.
So we can move forward with our assertions.
And now let's implement a rule number five.
Data must remain constant until ready becomes high.
So the property is checking that in the current clock cycle we are doing an ongoing transfer.
And this is the condition to identify such a scenario.
And if this is true then we must check that the data is stable.
Now let's also implement the assert property.
That's it.
Now let's see if our code compiles and runs correctly.
Everything run correctly.
We don't have any compilation issue or any simulation error.
And now let's try to change the driving in order to trigger this error.
And we can trigger this error by changing the data signal in the first clock cycle of the transfer.
So if we change it here, then our assertion should be triggered here at time 215 nanoseconds.
And we can do this in the driver.
We can change the data here after the first clock in the transfer.
So let's simply increment the data value.
And now let's try to see if our assertion is triggered at time 215 nanoseconds.
The simulation finished.
We did have an assertion triggered.
And now let's see in the log at which time this is triggered.
So this is triggered correctly at 215 nanoseconds.
So everything looks good.
Now let's comment this change from here.
And let's implement the same assertion for the offset and for the size.
So these are a rule seven offset must remain constant until ready becomes high.
And also rule number nine.
Size must remain constant until ready becomes high.
So let's do both of those in one go.
That's it.
Now let's try to change in the driver first the offset.
And we should get the same error as for the data, but this time for the offset.
At the same time 215 nanoseconds.
We had a compilation issue.
Let's fix it.
That's it.
There was an extra T here.
Let's run again.
Okay.
It looks like the assertion was triggered.
And let's see if the correct assertion was triggered.
So this time offset signal did not remain stable and the reported time is 215.
So this is correct.
And now let's see if we can trigger the assertion for the size.
Let's change the size here and run again.
Okay.
Again we have an assertion.
And let's check to see if it is size.
It is.
So the size signal did not remain stable.
And it is the same time 215.
So it looks like our assertions are working correctly.
So let's remove this code and try again to see if now with the correct driving everything will pass.
Okay, the simulation finished.
We don't have any compilation issue and also we have no errors in our log.
So everything looks good.
Now we can move forward to rule number ten.
Size cannot have value zero.
That's it.
Now let's try to run to see if we did any mistake.
Everything looks good.
We don't get any issue in our log.
And now let's try to change the driving in order to trigger this assertion and to trigger this assertion is very simple.
We just need to comment this line in which we drive the size.
So in this way size will always be equal to zero which is the reset value of this signal.
So let's try to see if our assertion gets triggered.
And it should be triggered with the first MD transfer that we drive.
So if we look on the waveforms it should be here at time 105 nanoseconds.
Because at this time we will not drive size equal to four.
So let's try this.
The assertion got triggered.
And now let's look at the first error in the log.
It is reported at time 105 nanoseconds as we expect.
Now let's put back this driving and move forward with the assertions.
And we should implement next rule number 12.
Error can be high only when valid and ready are high.
So let's do this.
That's it.
The property is pretty simple.
When error is high, we check that both valid and ready are high.
Now let's try to trigger this assertion.
And in order to trigger this assertion we need to alter the driver slave.
And we can do this by going here at the handle reset function and simply initialize the error signal to value one.
So the assertion will be triggered in the first clock cycle after reset.
And let's look first on the waveforms to see at what time we expect the assertion to be trigger.
Let's add the reset signal and the first clock cycle after reset is this one.
So we expect the assertion to be triggered at time 35 nanoseconds.
So let's see if this is correct okay.
Our simulation ended.
We have an assertion triggered.
And now let's look in the log and the assertion is triggered.
Indeed, at time 35 nanoseconds detected error signal high when ready and valid are not one.
So let's fix the code and try to see if everything runs correctly.
Now the simulation finished.
We don't have any errors in our log, so we can move forward to the last assertion in our interface, which is rule 15.
Offset plus size cannot be bigger than the data width in bytes.
That's it.
Now let's try to trigger this assertion, and in order to do this, we need to alter the driver master.
Let's simply increment here the offset because we know that we drive offset zero.
So we will drive offset one and size four.
So one plus four should be greater than the data within bytes.
So let's do this.
Okay our assertion got triggered.
And let's find the first failure.
It is at time 105 nanoseconds when data plus offset is greater than the data within bytes.
And this should correspond to the first transfer that we drive on the interface.
So the first one is here at 105 nanoseconds.
So everything looks good.
Now let's fix the offset here and see if our code runs correctly.
Now the simulation finished and looking on the log, we don't have any assertions or error triggered.
So with that, we finished implementing all the 15 rules in our MD interface.
And now the final rule this MD transfer cannot have an infinite length will be quite similar to what we implemented in the APB agent.
So we can go to the APB package and try to copy paste some of the codes from there.
So the first place to copy is in the agent configuration class.
We need to get that stack threshold field from there.
So this one we also need to copy it in our MD agent config.
And let's also copy its initialization.
And the getter and the setter.
These two functions.
We can copy paste them here.
And we can remove this check from here.
Because there is no limit on the MD transfer length, it can be also zero.
And now let's also copy from the APB package the check that we implemented in the monitor.
This one we can put it in the MD monitor here where we increment the length.
So let's align the code a little bit and add here an end.
And let's see if our code compiles correctly.
Everything looks good.
We don't have any compilation or simulation error.
And now let's try to change the value of the stack Stark threshold in our agent config, let's say to value two.
And this should trigger an error because we do have an access with a length bigger than two on this interface, and also on the text interface, we do have accesses with a length bigger than two.
So let's give it a try.
Our simulation finished and it actually finished at this point where it detected that the length of the transfer on the Take's interface already reached the stack threshold, which is two.
And let's also see the error message.
This is the correct error message that we expected, and in this case our simulation finished because the error was reported using the UVM error.
And in the case of our interface where we use directly the dollar error function, our simulation continued.
Now let's change back here the stock threshold to value 1000 and try to run again to see that everything runs correctly.
The simulation finished.
We don't have any compilation or simulation issue.
And with that we manage to implement all those 16 rules, part of the MD protocol.
And remember that in this tutorial, the new thing was how we implemented the checks for the data width in that static context.
And also here we saw how our code runs a little bit different on all of these three major simulators.
But in the end we manage to find a common implementation in our Systemverilog code, which was able to run on all those three simulators.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
