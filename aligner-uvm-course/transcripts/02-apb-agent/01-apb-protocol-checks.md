# APB protocol checks

*Chapter: APB agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to implement together the APB protocol checks.
These are the rules that we discussed in the previous tutorial.
The first four rules.
We will implement them as assertions inside the APB interface.
And the fifth rule will be implemented as a check inside the APB monitor.
As always, the starting point is the APB protocol checks practice project, which we will copy.
Make sure you unselect show output file after run.
The first thing that we have to do is to create a field inside.
The agent configuration class called has checks, which will be used to control if the checks are active or not.
So let's do this.
We will set a default value for this field equal to one.
This means that the checks are active and now we have to implement a getter and setter for this field.
That's it.
Now let's implement a similar field in the APB interface.
And we need a similar field here.
Because in the APB interface we cannot access.
The field has checks from the agent configuration class.
So let's do this.
And inside an initial begin block we will initialize this hash checks from the interface also to value one.
That's it.
Now what we need is a mechanism to synchronize the two fields.
The one from the interface and the one from the agent config, so that we ensure that they are always equal to each other.
The first step is to add some code in the setter of the hash checks from the agent config, so that whenever this field changes, it will update the one from the interface, and we can do this like so.
We must check here if the pointer to the virtual interface is set.
Otherwise we will get an error that we try to access a null pointer.
And this can happen if we call the setter for the hash checks before calling the setter to the virtual interface.
So based on this, we must ensure that whenever the virtual interface is set, we also synchronize its field.
And we can do this in the setter of the virtual interface.
That's it.
Now whenever the setter of the virtual interface or the setter for the hash checks from the agent configuration class is called.
There is a synchronization between the field from the agent configuration class with the field from the virtual interface.
Now, the only remaining thing is to make sure that the user will not change hash checks from the virtual interface directly, and we can build a small piece of code to look for such scenarios.
And we can do this in the run phase of the agent configuration class.
So let's try to do this.
That's it.
We build a forever loop in which we look for changes on the hash checks field from the virtual interface.
And when we detect such change, we ensure that the field from the virtual interface is always equal to the field from the agent configuration class.
If they are not equal, then we trigger an error.
We can verify this check by changing in the test that has checks from the virtual interface to see if the error is triggered.
So let's do this.
That's it.
So we change has checks to value zero.
And let's give it a try.
Okay.
The simulation ended.
We have one error here reported.
And if we scroll up the log we can see our error reported here.
One thing that we can change is to configure the simulation to stop at the first error it encounters.
And for this we have a plus argument that we can add to the run options.
And that plus argument is called UVM max with count equal to one.
So this means that we want the simulation to stop after one error.
Let's give it another try.
Okay.
And now we can see that our simulation stopped at the first error it encountered here.
Now that we have a field to control if our checks are active or not, let's start to implement the assertions.
And we can get rid of this code which triggered our error.
To implement easier assertions, we need two sequences to declare one, which will help us identify the setup phase, which is the first clock cycle of the app transfer, and one to identify the access phase, which is the second and the rest of the clock cycles part of an APB transfer.
So is this part.
So let's create these two sequences first.
The sequence for the setup phase.
There are two scenarios to identify the setup phase.
At this point here the p cell must be one.
And in the previous clock cycle p set should be zero.
So we have a rising edge in the p cell.
But we can also have the scenario in which two APB transfers are back to back.
This means that we have no gap like this one here.
And in that particular scenario we can identify the setup phase also by looking at p cell here to be equal to one but in the previous clock cycle.
So it will be this part here p cell should also be one.
But P ready.
Now it's one here.
So we look after this one.
So let's declare the sequence like this.
So this is our setup sequence.
Now let's create the access phase sequence.
And maybe let's change here the name to Setup phase.
And we can have also sequence access phase.
To identify the access phase is much easier.
PSL must be one here.
And P enable must be one.
So the sequence will be active in all these clock cycles.
So let's do this.
That's it.
Now let's create a property which will check the value of p enabled at setup phase.
So we have this property which is working on the pick lock, and we disable the property if the reset is active or we disabled the checks.
And the property says that at setup phase immediately in the same clock cycle we must have p enable equal to zero.
And now let's create an assert property for this one.
That's it.
Now notice here that I use dollar arrow instead of the macro from the UVM library UVM arrow in order to report the error message.
I'm doing this because the idea of creating the protocol checks inside the interface is to reuse these assertions during formal verification, and you might get into some issues when you try to run formal and also include the UVM package.
This may not be always the case, but my recommendation is that before you use the UVM library inside the interface, make sure that the formal tool used in your company is working with the UVM package also included.
If not, just use dollar error, which is native in Systemverilog.
Now let's try to break a little bit the driving logic so that our assertion is trigger.
So we can see that it detects correctly the scenario.
And to trigger this assertion it means that we also have to drive p enable equal to one in the setup phase.
So let's change a little bit the driver.
Let's see if our assertion is triggered.
We have a compilation issue I forgot to put here the semicolon.
Let's fix this and run again.
Our simulation ended and we can see throughout the log that the assertion is triggered.
Now let's fix the code in the driver to see if we get the assertion or not.
So now with the code fix, we should not get the assertion triggered in our log.
Okay, the simulation ended and the log looks clean.
Let's also create a property which checks that be enabled becomes one when entering the access phase.
So let's do this.
That's it.
The assertion is pretty simple.
In the next clock cycle after setup phase, be enable must be one.
So this equal here means that we are looking for the spin equal to one in the next clock cycle after setup phase.
Let's save and see if our code compiles.
Everything looks clean.
Now let's change a bit the driver in order to trigger this error.
And to do this, we simply have to comment the part which drives p enable equal to one.
In the access phase, we can see that the assertion is triggered, so it's working correctly.
Let's fix the code here.
And with those two assertions we actually implemented the first rule p enable must be asserted in the second cycle of the transfer.
Now let's implement the second rule.
Enable must be deasserted at the end of the transfer.
This rule is pretty similar in form with this one.
That's it.
So when we add in the access phase and be ready became one, it means that in the next clock cycle we exit the access phase.
So we enable must become zero.
Let's change the driver to see if we can trigger this assertion.
And we can do this by going at the end of the access and removing the part which drives p enable equal to zero at the end.
Let's save and see if our error is triggered.
Okay.
Our simulation ended and we can see the assertion triggered throughout the simulation.
Let's fix the code and run again to see if everything is okay.
And now our log is clean.
So with that assertion we implemented the second rule.
Now for the third rule.
Master driven signals must remain constant throughout the transfer.
So let's create assertions to implement this rule.
First let's check that enable will remain stable during the access phase.
The assertion is pretty straightforward.
During access phase, we know that being able must be equal to one.
Next, let's check that p right is stable during the access phase.
So here I made use of the dollar stable function which ensures that P enable during each clock cycle of the access phase.
It's equal to its value in the previous clock cycle.
So for the first clock cycle of the access phase it will use the value from the setup phase which should already have been set by the driver.
Now let's create the assert property.
For this one.
Let's see if our code compiles.
Everything looks good.
The assertions are not triggered, but let's change the driver a little bit just to see if we can trigger these, um, assertions for the P, right?
So if we go to the driver when we enter the access phase, let's change the value of the p right to see if our error is triggered.
So in the first clock cycle of the access phase we simply invert the value of p right.
Okay.
And we can see now in the log that our assertion is correctly triggered.
Let's remove this code and let's get back to the interface and create a similar assertion for the p address.
That's it.
Now the only remaining signal to verify is the right data.
But we must, um, check the p right data only for the right accesses.
So let's implement this.
So that's the only difference is that during the access phase, we also must check that this is a right access.
And only in that situation we check that P right data is stable.
Let's save and see if our code compiles correctly and runs.
Everything looks good.
The assertions are not triggered.
And with this we also implemented here rule number three.
Now let's implement the fourth rule.
APB signals cannot have unknown values.
So let's create assertions to check that each of the APB signals does not take unknown value.
The first signal will be pixel, and pixel can never have an unknown value in all the clock cycles in our simulation, of course, except during reset.
So let's do this.
The property is pretty simple.
In any clock cycle we use.
The function dollar is unknown for the pixel, which will return one if p cell is something like x or z.
If it is not.
It will return zero.
And now let's create the asset property for this one.
Now the next signal will be P enabled and the code will be similar to this one.
But we can give a little bit of tolerance here, and we can check that P enable does not take an unknown value only during an EP transfer.
So this means that only when p cell is equal to one, then we ensure that p enable does not take unknown values.
We do the same thing for the p address and the p write signal.
Now for the p write data.
The code will be similar, but we will add the check to be active only during the write accesses.
And for the read data, we must ensure that it does not take an unknown value only when the read data is returned.
So when the period is one and also slave error is zero.
So we have an okay access.
Next is the period which will be similar to this one.
It cannot have an unknown value throughout the transfer.
So we look only on the cell equal to one.
And finally the slave error which cannot have an unknown value when the response is ready.
So when p cell is one and p ready is one.
That's it.
Let's try to run the code and see if everything compiles and no assertion should be triggered.
Everything looks good.
The log is clean, no assertion is triggered.
And with those assertions, we implement the fourth rule.
APB signals cannot have an unknown value.
Now let's implement the fifth rule.
APB transfer cannot have an infinite length.
And as we discussed this will be implemented in the APB monitor.
So let's do this.
First we need to define what is the maximum length of the APB transfer at which we will trigger this error.
And for this let's create a field in the agent configuration class called stock threshold.
Let's assign a big value for this one.
Let's say 1000 clock cycles.
And let's create a getter and setter for this field.
That's it.
Now in the monitor we can implement the check in the part where we increment the length of the item so we can implement it here.
That's it.
So we trigger the error only if the hash checks it's one and we look on the length of the item.
Let's save and see if our code compiles.
Everything looks good.
The error is not triggered.
Now let's change a little bit the value of the stock threshold.
Let's say to value two and see if this short transfer is detected.
Okay we can see the error being triggered.
We know that we have accesses with length three.
And our check actually detected such accesses.
And let's put back the stock threshold to value 1000.
One other thing that we can add Odd is in the center of the stack.
Threshold.
We can ensure that the user does not set a value which is less than two, because we know that an APB transfer cannot be shorter than two clock cycles.
That's it.
Now, this is a perfect example of the benefits of using setters and getters.
You can use the logic inside the setter to check for the value configured by the user.
Let's see if our code compiles.
Everything looks good.
And with that we finished implementing all the rules that we discussed in the previous tutorial.
That's it for this tutorial.
Thanks for watching and see you in the next tutorial.
Bye!
