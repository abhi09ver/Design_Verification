# Update our random traffic test to make it more random

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to update our random traffic test to make it more random.
For this, we will create three virtual sequences.
In the first one, we will write random values in our configuration registers.
In the second one, we will read the status registers.
And finally, we will create a sequence which will send one random MD RX transaction.
The starting point is the EDA Playground project called "Tests: Random Traffic - Practice" which we need to copy.
And now let's resize the windows.
The first sequence that we will implement is our sequence for writing random values in the configuration registers.
So let's create the file for this class.
And now let's include it in our Aligner package.
That's it and now let's create our sequence class.
And the last thing that we need to declare here is the body() task.
That's it.
So I'm getting here all the registers and in this for loop I'm filtering out all the registers which are not writable.
After that I'm shuffling this registers queue and then for each register in this queue I'm randomizing the desired value and then calling the update() task.
Before we move on, I just want to mention one thing.
In this training, at some point we already created a sequence for configuring the registers.
This one.
And we could have updated the body() task of this sequence like we did here, but I wanted to create this new sequence in order to work only with virtual sequences.
Now let's move forward and let's implement our virtual sequence for accessing the status registers.
So let's create its file.
Let's include it in the Aligner package.
And let's try to copy paste the code from this sequence and adapt it.
And as always let's pay attention to those copy paste mistakes.
That's it.
So there are two differences: In this for loop we are filtering all the registers which are not read-only and then here we are calling the read() task.
Next, let's implement our virtual sequence for sending one random MD RX transaction.
So let's create the file.
Now let's include it in our Aligner package.
And now let's declare the class.
Now let's declare the handler to our MD simple master sequence.
And now in the constructor let's create an instance of this.
Next in pre_randomize() we must set the sequencer.
And finally in the body() task we must start this sequence.
And that's it.
Now that we declared all the virtual sequences that we need, we can update our random test.
And the first thing that we will do here is to declare our field for controlling the number of MD RX transactions.
That's it, so here I declared it and in the constructor I initialize it to value 300.
Now we can update the run_phase() task of the test.
And in here, first of all we need to put back this code which will trigger automatic responses on the TX interface.
That's it.
And now the rest of the code from this test we can actually delete.
And in here we will call our three sequences.
That's our sequence for writing random values in the configuration registers and now let's call our sequence for sending random MD RX transactions.
That's it, and now let's call our sequence for reading the status registers.
And that's it.
Now before we run our test, there is one more thing that we need to do here.
We might get into some false errors if we read the status registers immediately after we finish sending all the MD RX transactions.
This is because at this point here, there will be a lot of data in our RTL which needs to go out on the TX interface.
So you can imagine that at this point, at least the FIFO levels will be quite volatile.
So, if we read the status register at this point, there might be slight differences due to propagation delays between the environment and the RTL.
So, for this reason, it's a good idea to first wait for all the TX traffic to complete and only after that to read the status registers.
And to do this is quite easy, we simply add here some code to wait let's say 100 clock cycles.
And before we run our simulation, let's update the test in our Run Options.
So here we have now the register access test and let's change it to our random test.
That's it.
And let's also enable the waveforms and now we can start our simulation.
So it looks like our environment is slowly reaching the limits of the EDA Playground platform.
This warning is telling us that the waveforms file is too big and it cannot be displayed completely.
And there are other limitations that we can easily reach on this platform.
I am aware of at least two.
One is related to the number of lines that we are allowed to have in our log file, and I think currently this limit is 5000 lines.
And the other limitation that I know of is related to the CPU runtime of your simulation.
It cannot go over 1 minute.
Those limits might be updated in the future, so just be aware that when you are taking this tutorial you might encounter something like this.
For now, we can ignore this warning and we can add on the waveforms all the signals of our DUT.
So first let's add the APB interface and now let's add the MD RX interface and finally the TX interface.
So as that warning was suggesting, we are currently seeing only part of the waveforms.
And we have here our writes to the configuration registers, then we have our random MD RX traffic, but we cannot see the reads from the Status register.
And just to be able to see everything on the waveforms, we can actually go to our test and limit the number of MD RX accesses to 100.
And now let's save and run again to see if we can visualize the entire waveforms from our test.
Our simulation finished and now we can clearly see the writes to the configuration registers, then our 100 random MD RX transactions, and then after 100 clock cycles we can see the read from the Status register.
And let's zoom here where we are writing the configuration registers to see what is happening there.
Our RTL has 3 registers which are writable but here we are only seeing 2 accesses.
And let's also add on the waveforms the APB address signal.
And we can move it up by pressing this button here.
And based on the address, we can see that our sequence is writing to the Interrupt Requests Enable register and to the Control register.
But it is not writing the Interrupt Requests register.
This might be due to the fact that when we randomize the register, the desired value was generated with a value equal to the mirrored value.
In this way, when we call the update() task, nothing will happen.
Because there is no difference between the desired value and the mirrored value.
So then let's try one more run to see if we get an access to the Interrupt Requests register.
Our simulation finished and now let's zoom in the region where we are writing the configuration registers.
And we can see that also this time the Interrupt Requests register was not written.
Debugging this issue is quite a difficult task and even experienced verification engineers are not aware of this behavior in order to adapt their code properly.
But I can show you what is the root cause of this behavior and how we can easily fix this.
In our sequence in which we write the configuration registers, first we randomize the desired value and then we call the update() task.
In this update() task, the UVM library will trigger the APB access only if the desired value generated here is different than the mirrored value.
Now let's look in our registers package and see how we declared the Interrupt Requests register.
This is our class which is modeling the Interrupt Requests register.
In the build() function, we called the configure() function of all the register fields.
For each register field, we did set this field is_rand to value 1 and with this line we said that we do want this register field to be randomized.
However, its access right is write-one-clear and it is the same for all the register fields in this register.
Now let's look on the declaration of the UVM register field from the UVM library.
I opened here the file from the UVM library in which this uvm_reg_field class is declared.
And let's go to the configure() function.
This is the declaration of this configure() function and let's look at the end of this function.
The problem comes from this case.
In this case statement, this field is_rand it's overwritten with value 0 for all the register fields which are not writable.
In our case, all the register fields from the Interrupt Requests register are declared as write-one-clear.
This means that this is_rand value is reset back to 0.
And the effect of this is that in this if statement from here, the rand_mode() of this value it's set to 0.
This means that when we randomize the register field, the desired value will not change.
So knowing this, the fix is quite simple.
After we call the configure() function of all the register fields, we set back this rand_mode() to value 1.
So let's do this.
Here, after we call all the configure() functions, we have to set that rand_mode() for the value field in each register field to value 1.
That's it and now let's give it one more try to see if this time our Interrupt Requests register will be written.
The simulation finished and we can immediately see that our fix worked because we have now three accesses to the registers.
So let's zoom a little bit just for confirmation and we can see our accesses to all the writable registers.
I told you in the previous tutorial that even after this update our random test will not verify some of the features of our RTL.
And let me add on the waveforms some signals which will show what features are never tested.
From this registers submodule let's add on the waveforms the drop counter and also the fields of the Interrupt Requests register.
Now, in our test, even though we are writing all the writable registers and we are reading all the read-only registers, our current implementation of the test will never clear this drop counter when it is not zero.
This is because, after we are sending all the MD RX transactions, we are no longer writing to the Control register.
Remember that in the Control register we have that CLR register field which is clearing this drop counter.
The same thing is valid for the interrupts.
We have the possibility to clear these interrupts by writing to the Interrupt Requests register.
But because we are not doing this here, those interrupts will never be cleared.
But we can easily fix this by creating a loop inside our test.
So let's go to our random test.
And we can put the code in which we are calling our virtual sequences in a repeat statement.
That's it.
So I'm calling these virtual sequences two times.
And now let's save and see how our waveforms looks like.
Our simulation finished and we can see here in the middle that we are reading the Status register and then we are writing the configuration registers.
And let's see now if that drop counter is cleared or the interrupts are cleared.
We can see the status counter is cleared here from value 16 to value 0 and we can see that also one of the interrupts is cleared here.
And let's also look in the log to see if we get any errors.
And we don't have any UVM errors so it looks like our test is passing.
However, if you run this test several times you will eventually get a seed in which your test will fail.
Let me try this also on my end and show you why the test is failing.
So, finally, after I run this test 11 times, I manage to find the seed for which the test fails.
And let's look at the error message.
And the error is saying that there is a mismatch detected on the TX data.
And let's look on the waveforms to see when this error appears.
And we can see that this error appears right after we start our second loop in the test.
To debug this problem again it will take some time and I will tell you exactly the reason why the test is failing.
After we finish sending all these MD RX transactions, we again write to the configuration registers.
But the problem is that at this point there is still data in the RTL and also in the environment.
Even though we waited here for 100 clock cycles for all the data to go out on the TX interface, some of the data can remain inside the RTL in that intermediate buffer.
This is because the RTL and also the environment are waiting to get more data on the RX interface to have enough information to align it.
And the problem is that our test is changing the configuration of the RTL while there is data inside.
And this leads to unpredictable behavior.
We cannot change the configuration of our device while it has data inside.
And for this reason, we need to update our test, not to call the sequence which is writing the configuration registers if there is data in our RTL.
To do this, we need to create a function in our model which will tell us if there is data stuck in the model or not.
But before we code that function let's save the seed with which this test failed in order to be able to reproduce this scenario.
So we can take the seed number from here and put it in our Run Options.
That's it.
And now let's go to the model class.
And let's implement a function called is_empty() which will return 1 if there is no data in our model.
That's it.
So the function will return 0 if there is data in the RX FIFO or in the TX FIFO or in the intermediate buffer.
Otherwise it will return 1.
And now we can make use of this function in our random test.
Here we can call this sequence only if the is_empty() function from our model will return value 1.
So in the beginning of the test the model will be empty so this code will be executed but at the second iteration of this repeat loop we will call this sequence only if the model is empty.
And now let's save and see if this fixed our test.
The simulation finished and we can immediately see that our fix worked as here in the middle we are only reading the Status register, we are no longer writing all the configuration registers.
Let's also double check the log.
And we don't have now any UVM error.
And the last thing that we need to do is to change the seed to random.
And let's try one last run and it looks like this run passed.
That's it for this tutorial.
We managed to update our random test to make it more random in order to test all or most of the features of our RTL.
What we experienced in this tutorial it's quite close to what you'll experience in a real project.
When you create random tests and try them a few times you'll see that those tests will pass, but when you start to run those tests in a regression and you have thousands of runs, some of those runs will fail with scenarios which you did not anticipate in the beginning when you coded that test.
And this is normal, it's part of the job.
Throughout the project you'll do incremental updates to those tests in order to cope with all those scenarios.
And even if the test will pass in all the runs from your regression, you can still have surprises when you look over the coverage and realize that some of the features are not tested.
So be aware of this and try to anticipate for these iterations when you will be working in a real project.
And as always, I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
