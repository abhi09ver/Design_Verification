# Update the register access test to make it more random

*Chapter: Debug and tests · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to update the register access test to make it more random.
For this, we will start from the run_phase() in parallel two sequences.
In the first sequence, we will generate random traffic which will always access the registers.
In the second sequence, we will generate random traffic for which the addresses will always point to locations in which there is no register mapped.
The starting point is the EDA Playground project called "Tests: Register Accesses - Practice" which we need to copy.
Now let's resize the windows.
Now let's implement our random register access sequence.
The first thing that we need to do is to create the file.
Now let's include this file in our Aligner package.
That's it.
Now let's go back to our file and declare the class.
And that's it.
Next, let's declare this number of accesses field also with a soft constraint on it.
That's it.
Now let's declare this get_random_access() function to return a random direction for the access.
That's it, so I'm generating the result to be either UVM_READ or UVM_WRITE and then I'm returning the result.
We need this constraint here because this type can have other values like UVM_BURST_READ and UVM_BURST_WRITE.
Next, let's declare this task for waiting a random number of clock cycles.
That's it.
And now let's declare the body() task of our sequence.
That's it.
So the code is pretty simple.
I'm getting here all the registers from our register block and then in this for loop I'm accessing a random register using a random direction.
And after the access is completed then I'm calling this wait_random_time() task.
Next, let's implement our sequence for accessing unmapped locations.
So let's create the file.
Now let's include it in our Aligner package.
And now let's declare the class and we can also take some of the code from our random sequence.
And we can also take the task for waiting a random number of clock cycles.
So this one.
Next, let's implement this function for getting the addresses of all the registers.
That's it.
So for all the registers in our register block and for all the bytes of the register I'm pushing into this addresses queue the address of that register byte.
And now let's implement the body() task of this sequence.
That's it.
So the code is pretty simple.
I'm getting here all the addresses of the registers and then in this for loop I'm starting this simple APB sequence.
The only constraint for this sequence is for the address not to be inside this addresses queue.
After the item is finished, I'm calling this wait_random_time() task.
Now let's update our register access test to use these sequences.
First, let's declare these two fields with which we will control the number of accesses on each branch of the fork.
That's it, and now let's put in the run_phase() task our fork on which we will call the two sequences.
That's it.
So we have our fork with the two branches.
On the first one we are calling the sequence which will do random register accesses and on the second branch we have our sequence which will do unmapped accesses.
Before we try to run let's update the test in our Run Options.
So here we have our random test and let's change this to our register access test.
That's it and now let's save and run.
The simulation finished and now let's look through the log and it looks like we don't have any errors.
And let's see how our log looks like.
So we have a lot of reads and writes to our registers.
But for unmapped accesses we are not getting currently any message.
Let's try to run one more time our test and see what happens.
The simulation finished and if we look at the log we can see that now we have an UVM error.
And let's see exactly what error we are getting.
So it looks like there is a mismatch when reading the Interrupt Requests Enable register.
The mirrored value is 0 but the DUT returned 1F.
Because this is the only access a read from the Interrupt Requests Enable, it means that the RTL and also the environment are returning the reset value of this register.
So, our environment thinks it should be 0, but the RTL thinks it should be 1F.
So, either it's a bug in the RTL or it's a bug in the environment.
And to clarify this, we can look in the specifications.
In the Aligner datasheet, we can go to the Registers chapter to this Interrupt Requests Enable register.
And this table shows the reset value of all the register fields inside this register.
And we can see from this column that the correct reset value is zero.
This means that our environment is right and we just found an RTL bug.
Our previous run of this test passed because randomly the first access performed in this Interrupt Requests Enable register was a write, so the reset value was overwritten.
But if you get a seed for which the first access into this Interrupt Requests Enable register is a read, then the test will catch this bug.
In a regular project at this point you will have to report this bug to the design team and the design team will have to provide a fix.
But in our case I can show you exactly where you can fix this in the RTL code.
You can find this bug in file cfs_regs at line 175.
Here, in this always construct, you can find the reset values of all these register fields from the Interrupt Requests Enable register.
We can change these values from 1 to 0.
That's it.
And now let's check to see if we fixed this RTL bug.
So, first of all, we need to take the seed for this test.
And the seed is mentioned in the log at this line, so we can copy this value and put it here in our Run Options.
Now let's look again on the error.
And this access is the fifth one: 1, 2, 3, 4, 5.
So let's try to run our test and see if the fifth access is also to the Interrupt Requests Enable register and observe what value is returned by the RTL.
The simulation finished and now let's look at the beginning of the log.
And we can see that the fifth access is a read from this Interrupt Requests Enable register and the RTL returned correctly value 0.
Now let's do one more thing before we end this tutorial.
Let's change the seed to be again random and let's also look on the waveforms.
And let's add the signals of the APB interface.
And let's zoom a little bit to understand better what is happening.
And you can see that our two sequences, the one which is driving random register accesses and the one which is driving unmapped accesses, are fighting for access to the interface.
So we have here an access to a register, then an access to an unmapped location, then again an access to a register.
And depending on the generated time in that wait_random_time() task, we might get scenarios in which, for example, there are two or three consecutive accesses to the registers followed by an unmapped access or vice versa.
And let's see if we can identify such a scenario on our waveforms.
For example, here there are two accesses to unmapped locations followed by an access to a register.
And you can play around with the generated values from that task in order to get different patterns on the waveforms.
That's it for this tutorial.
We managed to make our register access test more random and we also found with our new test a bug in the RTL.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
