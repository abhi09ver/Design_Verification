# Scoreboard check for the interrupt request

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to implement together the scoreboard check for the interrupt request.
This means that in our scoreboard class, we have to add the API represented here with blue.
Also, in the environment configuration class, we have to add the threshold field with the getter and the setter.
And finally, in the interface, we will add the interrupt request and the reset signals.
The starting point is the EDA Playground project called "Scoreboard Check: IRQ - Practice".
So as always we will have to copy this project.
And now let's resize the windows.
The first thing that we will add is our queue of expected interrupt requests.
So let's add that queue in our scoreboard class.
That's it and now in the handle_reset() function let's delete all the elements from this queue.
And that's it.
Next let's add our queue of process pointers for the watchdog task.
That's it, so I'm declaring the queue here and then in handle_reset() I'm killing all the processes from this queue.
Next, let's add the threshold field in our environment configuration class with the getter and the setter.
And that's it.
Next, let's add this watchdog task.
And because the code is quite similar to what we implemented before, we will copy the code from the TX item watchdog and then we will adapt it.
And that's it!
Next, let's add our non-blocking function for starting the watchdog task.
And that's it.
Next, let's implement the write() function through which we get from the model the expected interrupt requests.
And remember that in this function we will have to allow at maximum 5 elements in our expected interrupt requests queue.
And that's it.
Next let's add in our interface the reset and the interrupt request signals.
That's it and now let's connect these signals in the testbench.
So that's the reset and now let's connect the interrupt request.
And that's it.
Now let's add in the scoreboard the logic which will monitor that output from the DUT and the first thing that we will have to add for this is the pointer to the process of rcv_irq() task.
That's the declaration and now in handle_reset() let's kill this process.
And that's it.
Next, let's implement our rcv_irq() task.
And remember this must be a forever loop which will look when the irq output from the RTL is 1 and at that point the code will be quite similar to what we implemented in this write_in_agent*() functions.
So let's do this.
That's it.
The code is pretty simple.
We have a forever loop in which we wait for the output from the DUT irq to be 1.
And at this point, we make sure that also the model generated an expected interrupt request.
Otherwise, we trigger an error saying that the irq coming out of the DUT is unexpected.
If the model also generated an expected interrupt request, first we go through this part and we pop the first entry from our expected queue and we kill the process associated with the watchdog task.
The last thing that we will have to add in the scoreboard is our non-blocking function for starting the interrupt request task and we will call this non-blocking function as the last thing in our handle_reset() function.
So let's do this.
So that's our non-blocking function and now let's call this function in handle_reset() here.
And with that, our scoreboard check is complete.
But before we run our test and see how the code is performing, we still need to do another thing in the test.
And if you look in the Aligner datasheet in the "Interrupt Request Enable Register" chapter, you'll see that at reset all the interrupt requests should be disabled.
So what we need to do in our test is to write this Interrupt Requests Enable register with value 1 for all these fields.
So let's do this.
Here, just before we write a random value in our Control register, let's call the write() function of the Interrupt Requests Enable register.
And that's it.
So with this line we are enabling all the interrupts and now let's save and see how our test is behaving.
And before we run let's enable this "Open EPWave after run".
Our simulation finished and now let's look in the log to see what happened.
And it looks like we have an UVM error.
The interrupt request expected from this time was not received after 10 clock cycles.
So now when we get an error like this, the first thing that we have to do is to save the seed.
Remember that we run with -svseed random.
And this means that if I press again on the run button, the next simulation will be different than this one.
So because I want to debug this exact scenario, I have to search for the seed and save it.
So the generated seed was this one, so I will take this number and put it here.
So this means that when I run again the simulation, my simulation will finish at exactly the same time at 825 with this error message.
So let's give it a try.
Remember that the randomization depends on the way you wrote your code on the tool version from here, so there is a good chance that even if you set the seed number like I did, you might not get the exact same results.
Nevertheless, the problem that we are debugging now also exists in your code, so you will most likely encounter the exact same scenario if you try to run more random tests.
Now let me show you how we can find out what's the problem here.
So first let's double check that the simulation ended in the same way when we set the seed number and it is the same at time 825 we get the exact error.
So this is saying that our model generated this interrupt request at this time but the RTL did not output that interrupt.
So first let's add on the waveforms, the clock, and the interrupt request output signal.
So it looks like the RTL generated 6 interrupt requests.
And based on the error message saying that there is an expected interrupt request which was not received, this means that our environment should have generated 7 interrupt requests.
So let's see if this assumption is correct.
And to get this information, we have to search the log for the message which we are printing when we are generating an expected interrupt request and every time we are doing this we are printing a message like this one.
So if we search after this text we should get in the log the points where we are generating expected interrupt requests.
And as you can see here, we have 7 matches in our log.
So this means that we are generating 7 interrupt requests.
And this is aligned with the error message which is saying that the environment did not detected an interrupt request coming out of the RTL.
The model generated 7 expected interrupt requests while the RTL generated 6 interrupt requests.
Now what we can do is to look on the time when the model and the RTL generated these interrupt requests.
So let's take the first expected interrupt request from the environment, which is this one, and we can see that the environment generated this expected interrupt request at time 256.
And if we look on the waveforms, time 256, it's around here.
And you can see that the RTL generated the interrupt request a little bit later.
The problem is that we cannot identify exactly which interrupt is missing from the RTL because the time when the model generates the interrupt and the RTL generates the interrupt differs.
And when we have a difference in time like this between the model and the RTL, we cannot really use the time because in scenarios in which the interrupts are quite close like we have here, we can't identify the one-to-one relationship between the environment and the RTL.
But what we can do is to look in the log and see the reasons why the model generated these expected interrupt requests.
So we have the first interrupt request generated due to RX FIFO empty.
The second one also due to RX FIFO empty.
Then we have the third one due to TX FIFO empty.
So we have 2 and 1, 3 and 1, 3 and 2, 4 and 2, 4 and 3.
So this is the last one.
So we have 4 interrupts generated due to RX FIFO empty and 3 interrupts due to TX FIFO empty.
If you were in a real project, this would be a good time to go and talk with the design engineer to ask for help in understanding why the RTL generated these 6 interrupt requests.
And in such a case, the design engineer would tell you to put on the waveforms some signals which gives this information.
And we can find these signals in this regs submodule.
You should search after some signals which starts with edge, like these ones.
So these edge signals will give us the information about the reason why the RTL generated the interrupt requests.
We can see on the waveforms that also the RTL has two reasons for generating the interrupt requests: "RX FIFO empty" and "TX FIFO empty".
And RTL generates the interrupt request due to RX FIFO empty 4 times just like the environment, but only 2 times due to TX FIFO empty.
So that's a very important clue because now we can look in the RTL on the reason why it generated only 2 interrupt requests due to TX FIFO empty and not 3 like the environment.
And this is another point where we should ask for help from the design engineer in order to understand why the RTL generates only 2 interrupt requests due to TX FIFO empty.
And to understand this, a design engineer would tell us to add several signals on the waveforms, and these signals will give us the following information: the TX level information and then the control signals which are pushing and popping from the TX FIFO.
So let's add these signals on the waveforms.
We can get the TX level information also from this regs module.
That signal is called status_tx_lvl.
For the control signals for pushing and popping from the FIFO we should select the TX FIFO module and here we have two pairs of signals valid and ready for push.
So we have push_valid and push_ready and on the pop interface pop_valid and pop_ready.
So inside the RTL, there is a push inside the TX FIFO when push_valid and push_ready are both 1.
So if you look, for example, at this point in time, we have push_valid and push_ready both 1 and you can see the TX level incrementing.
The same logic is on the other side when popping information from the TX FIFO when both of these signals are 1, there is a pop from the TX FIFO.
And at that point the TX level is decremented like we have here.
You see the TX level goes from 6 to 5 and here from 5 to 4 and so on.
Now what's important for us is to see when the RTL generates this TX FIFO empty and you can see that it generates this interrupt request when this TX level goes from 1 to 0 as that is the moment when TX FIFO becomes empty.
So we have two points here, and here.
But one very interesting moment in the RTL is here, and let's zoom a little bit in this region to understand what is happening there.
At this point TX level was 1 and at the same clock cycle there is a push and a pop from the FIFO.
So at this point this only entry in the TX FIFO is popped out and in the same time a new information is pushed in the TX FIFO.
So the level remains constant at 1, even though we have this glitch here, the TX level does not go from 1 to 0 so that the interrupt request is generated.
And now let's search in the log to see if we have a similar scenario in which we have a push and a pop from the TX FIFO in the same simulation time.
So let's search from the beginning for this entire message.
So we have 3 matches for this string as we have 3 expected interrupt requests generated due to TX FIFO empty.
At the first match here, there is a pop at this time, 725, but at this time there is no push.
So let's move forward for the second one at time 555.
Again, we have only one pop at this time but no push.
And then the last one at 645 we have this exact scenario where we have a pop and a push both at the same time at 645.
There is a small difference with the RTL.
Initially our TX level was 0, but then when we are doing the push and then the pop, our TX level goes to 1 and then to 0 in the same simulation time.
And this is why we are generating this TX FIFO empty interrupt.
However, this is not the behavior of the RTL.
The RTL only looks on the TX level and if this one does not go from 1 to 0, then there is no TX FIFO empty interrupt generated.
You might argue here that at this point, however, there was a push and a pop in the same simulation time from the TX FIFO, so it makes sense to generate a TX FIFO empty interrupt, but this is debatable based on what the TX FIFO empty interrupt should represent.
In such a scenario, if there is a debate on the correct behavior of the RTL between the verification engineer and the design engineer, then you should ask the concept engineer to clarify what should be the expected RTL behavior in such a case.
In our scenario, we should consider that the RTL behaves correctly and the TX FIFO empty interrupt is generated only when the TX level is decremented from 1 to 0.
So, if there is a push and a pop in the same simulation time, the level of the FIFO, either the TX or the RX remains constant, so there is no need for an interrupt request.
And this is valid not only for the empty interrupt request, but also for the full interrupt request.
This means that our environment has a synchronization issue.
Our environment should identify a scenario like this one in which we have a push and a pop in the same simulation time, and in such a case, it should not generate an expected interrupt request.
And we will fix this synchronization issue in our next tutorials.
And just want to iterate again.
You might not get into the same exact scenario as I did using this seed that I'm using here.
And this depends on maybe the tool version.
At the moment when you are taking this training, this tool version might be changed.
So this would influence maybe the generation, but nevertheless, this synchronization problem exists also in your environment.
And you can get to a similar scenario if you are running the test with random seed several times.
And if you do this, you should look for a scenario in which you have these two messages, the push and the pop happening at exactly the same simulation time.
However, if your test is still failing but you don't get this scenario in which you have the push and the pop in the same simulation time, I just want to let you know that this is okay because our model has not only 1 but actually 3 synchronization issues.
But we will deal with these problems later.
For now, our target was to implement the check in the scoreboard for the interrupt request and we managed to do this successfully.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
