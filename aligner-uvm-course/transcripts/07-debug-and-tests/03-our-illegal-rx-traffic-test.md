# Our illegal RX traffic test

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together our illegal RX traffic test.
To accomplish this, first we need to create a virtual sequence from which we drive only illegal RX traffic and then we can create our test in which we use this new virtual sequence.
The starting point is the EDA Playground project called "Tests: Illegal RX Traffic - Practice" which we need to copy.
And now let's resize the windows.
First let's create our virtual sequence which extends from our RX virtual sequence.
In here we have to declare this field for the Aligner data width and we will use this field to define the constraint for illegal RX transactions.
Now let's create the file for that virtual sequence class.
Now we can include this file in our Aligner package.
And now let's declare the class.
Now let's declare the field for the Aligner data width.
That's the declaration and now in pre_randomize() we can allocate its value.
And finally, we can add the constraint for illegal RX transactions.
That's it.
So an illegal access is defined by one of these two conditions.
In the first one we are saying that the data width in bytes plus the offset modulo size must be different than 0.
And the second condition is saying that the data size plus offset must be greater than the data width in bytes.
Now that we have our virtual sequence we can create our test.
So first let's create the file.
And now let's include it in our test package.
That's it.
And now let's go back to our file and declare the class.
And here in the constructor the first thing that we have to do is to set that number of MD RX transactions to 300.
That's it.
And now the last thing is to override the RX virtual sequence with our new one.
And that's it.
Now before we run we need to update our test in our Run Options.
And let's also enable the waveforms.
The simulation finished and we are again getting this warning because we increased the number of MD RX transactions but we can ignore this warning and we can add on the waveforms all the signals from our DUT interfaces.
Even though we are not seeing the entire waveforms just like that warning was saying, we can immediately determine that our constraint worked because all the accesses on the MD RX interface have the error response.
This means that nothing goes inside the RTL, so on the TX interface we are not seeing any traffic.
Let's also look in the log to see if our test passed.
And we don't have any UVM errors.
However, if you run this test several times you will eventually get a seed for which the test fails.
So let me try this on my end.
The simulation finished and this time I did not get that warning so something is different.
And if I look in the log I can see that I have one UVM error.
So let's see what is the error message.
So we are getting a DUT error from our scoreboard and it is saying that the RTL did not output an interrupt.
As before, the first thing that we need to do is to save the seed in order to be able to reproduce this bug every time we want.
So we need to take the number from here and add it in our Run Options.
That's it.
So now with the seed saved we can debug our failing test.
So let's look again on the error message.
And from this error message we cannot figure out what is the reason for the environment to generate this expected interrupt request.
But we can easily fix this by enabling the messages related to the interrupts.
So for this we need to go to our messages.f file.
And in here we can take out the messages coming from our MD agents and enable the messages related to our interrupts.
So let's do this.
That's it and now let's save and run again.
The simulation finished and let's look on the log.
And this time we can easily see that our environment generated an expected interrupt request due to the drop counter reaching its maximum value.
So let's add on the waveforms the drop counter from the RTL and also this interrupt request.
And we can find that information in the regs submodule.
So this signal is the drop counter.
And let's also add the Interrupt Requests register field.
This one.
And we can see that the Interrupt Requests register field from the RTL also became 1, so let's zoom a little bit here.
We can see that the drop counter reached the maximum value, the interrupt request register field was set to 1, but the interrupt output did not became 1.
Let's check the field from the interrupt request enable register.
So is this one.
This field is 1, so the RTL should have generated an interrupt request here.
If we were in a real project at this point we can confirm that this is a real bug and the next step is to report this bug to the design team.
But in our case I can show you exactly what is the problem in the RTL code.
So let's go to this regs module.
And let's jump to line 164.
In this assign statement the output interrupt request is built.
And you can see that this code is using all the interrupts except the one for the drop counter.
So we can add the code for that interrupt here.
And the name is max_drop. and also for the enable signal.
This is quite a common bug which you can also encounter in a real project.
The designer simply forgot to add this last interrupt request to this logic.
Now let's save and try to run again our test.
The simulation finished.
We are getting the warning saying that the waveforms file is too big.
And let's look in the log.
And this time we don't have any UVM errors, so the RTL fix worked.
Now the last thing that we need to do is to change back the seed to the random value.
That's it.
And now let's try one more run.
The simulation finished and this time, if we look in the log, we don't have any UVM errors.
That's it for this tutorial.
We managed to implement our test for driving illegal RX traffic and with this test we also managed to find an RTL bug.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
