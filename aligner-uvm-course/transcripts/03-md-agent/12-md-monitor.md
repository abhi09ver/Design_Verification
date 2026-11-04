# MD monitor

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the MD monitor.
This is the current state of our verification environment and in this tutorial we are going to talk about the monitor inside the MD agent.
So the first thing that we have to do is figure out how to code this item monitor.
So basically what kind of information we need to put inside this class.
And while we're here, let's remember that the UVM sequence item has this inheritance tree.
And relevant for us is this UVM transaction, because we will use some of the API from this class to figure out what kind of information we want to put in our item.
Moon, we need to look on the waveforms to see how an MD transaction looks like.
So just like for the APB, we will have to put some information regarding the previous item delay.
So this will represent the number of clock cycles between the end of the previous item and the beginning of our current item.
We can also put the length in clock cycles of our current MD transaction.
We will code the data as a list of bytes, so we will code the information from this data bus and from the sys bus.
Then we will put the offset and the response.
So if we look on the diagram of our item on class we will have to code those five fields.
There.
One thing which will be different in this MD monitor in comparison with what we coded in the APB monitor, is the way we pass the information from the monitor to whoever is listening for that information.
So this is coded in the way we call the right function from the output port.
So if you remember from the APB monitor we called this write function whenever we collected the entire information of a transaction.
So the equivalent in the MD protocol is to call this function here at the end of the transaction, or here for this item or here for this one.
So remember that the end of an empty transaction is when valid and ready are both high.
But what we will do for this MD protocol is to call this output port dot right also at the beginning of a transaction.
So in this case will be called here when there is a rising edge of valid for example.
And we want to do this for several reasons.
For example, we want to know that the transaction started here in order to be able to predict in our scoreboard how long this transaction will have to be based on the fill level of the internal Fifos or another use case for this is when we have to implement the slave driver.
Maybe we want to have a particular error response based on the offset and size.
But one important thing to notice here is the following.
At the beginning of a transaction, and also at the end of a transaction, we will send exactly the same information, this item one through exactly the same port.
So the question is how we will know if the information received through this port will be the information from the beginning of an item or at the end of an item.
And the solution comes from the API of the UVM transaction.
So this class provides these two fields begin time and end time.
These are declared as private, but they are set through some special functions, either from the UVM transaction or from the UVM component.
So at the beginning of a transaction, we will set this begin time to whatever simulation time is here.
And of course, at the end of the transaction we will set this end time and the UVM transaction also provides this public function called Isactive, and this one returns a bit, so it will return value one before this point and value zero after this point.
So this is how we know if an item received through this port is at here, because at this point is active will return one or here where is active will return zero.
As I told you this begin time and end time are set through some special functions and let's see how these are set.
We will set the begin time by calling this begin to begin transaction function from the UVM component.
So from our monitor and we will pass as an argument the item which we will build inside our monitor.
So this class here and after we set this begin time we will call our output port dot.
Right.
And the same thing for the nth time.
We will set this one via this end transaction function.
The same from the UVM component.
But one important thing to notice here is that in the MD protocol, it's possible to have a transaction of only one clock cycle, and this is possible because the ready can become high in the same time as valid.
And you can also see this behavior on the waveforms.
With our current implementation of the environment, you will see this MD ready being high for exactly one clock cycle when also MD a valid is high for one clock cycle.
So this means that we will detect the beginning of a transaction in the same simulation time with the end of the transaction.
So for this item we will detect the beginning here.
And also the end will be in the same simulation time because red is already one here. and this would be fine for most of the situations, but in our case, where we have to implement the slave driver in which we want to give a particular response based on the offset and size, this would not be okay, because if we send to the slave driver the information that this item started here, it will not have time to prepare a response because the response should already have come here.
And in order to solve this problem, we have to detect the beginning of a transaction a little bit earlier.
But to do this, we have to sample the signals not on the positive edge of the clock, but just a little bit to the right.
And in our case, we will sample them one nanosecond after the positive edge of the clock.
So this means that in this case the beginning of the transaction will be here.
And also for this one the beginning of a transaction will be here.
The code to do this is quite simple.
In our monitor we will wait for the positive edge of the clock so it will be here.
Then we will wait for one nanosecond and then we will evaluate if this is the beginning of a transaction.
But having this one nanosecond here is not ideal, because this might not work for all the scenarios.
And to solve this we will actually create in our agent config a field called sample delay start transaction of type time.
And we will use this field to introduce this delay.
But in our environment we will set this to one nanosecond.
As you might have guessed, there is more to this oven transaction than this.
Begin time and end time.
This class, together with some API from the UVM component, allows you to put on the waveforms something like this.
So you will see all the information collected by the monitor in this form.
And this is much more easier to look and understand than looking on the signals.
This MD protocol is quite simple and you can figure out relatively quickly where is the begin of a transaction and where is the end.
But there are protocols much more complicated, in which it is not so easy to understand this, but seeing this information in this form makes your life much more easier.
And this can help you a lot.
When you debug some complex scenarios, there is some code which you have to write in order to be able to put on the waveforms the information like this.
But we will not implement this code because on EDA playground platform this is not yet possible.
But all the major simulators supports this feature.
If you want to read more about this oven transaction, you can find some information in the UVM class reference.
And in here there is this chapter under the base classes related to the UVM transaction.
And you can read more about this class here.
And also in the components under the UVM component there is a section about transaction recording.
And if you scroll down here so is this one recording interface.
You can see all the available functions which you have in order to control this UVM transactions.
And in our case we will use this begin TR and end TR functions.
Another source of information for you would be this article that I wrote.
Debugging tip.
Look at the bubbles.
And in this article I'm describing, uh, what exactly you have to do in order to be able to put on the waveforms.
The information in this format.
You can find the link of this article in the resources of this tutorial.
Regarding our MD monitor, the API of this class will be quite similar to what we coded in the APB monitor, so we will copy paste a lot of the code from there.
And out of all these functions and tasks, the only difference between the APB and this MD monitor will be in this collect transaction task, in which we will collect this MD transaction.
That's it.
For this tutorial, we talked about the MD monitor item with all its fields and how we will collect them.
We also touched a little bit on the API of the Uvean transaction, and we discussed the API of our MD monitor.
In the next tutorial.
We will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
