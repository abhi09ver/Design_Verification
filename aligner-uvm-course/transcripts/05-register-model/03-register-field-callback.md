# Register field callback

*Chapter: Register model (RAL) · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the register field callback.
From the Wikipedia, the definition of a callback is this one: A callback is a function that is stored as data and designed to be called by another function.
The UVM library provides the mechanism to use this callback design pattern in different classes of the library, but in this tutorial we will talk about the callbacks related to the register field class.
And let's try to identify in this callback definition the classes and functions part of the UVM library which are implementing this callback.
Because we are talking about the register field callback we need to look on the API of the uvm_reg_field.
And the relevant function from this API is this predict() as this is the function which will call our callback function.
And to make things simpler let's get rid of the rest of the API from the uvm_reg_field and just keep this predict() function.
Next, let's focus on this part: "a function stored as data".
In SystemVerilog, in order to store a function as data, we need to put that function in a class and then store a reference to that instance of the class.
In our case, the class which contains the function is this one: uvm_reg_cbs.
So this uvm_reg_cbs is this part of the definition: "as data, (a reference)".
So we will need to store a reference to this class.
And the function defined in this class is this one: post_predict().
And let's see the entire inheritance tree of this uvm_reg_cbs.
So this one inherits from uvm_callback and uvm_callback is an UVM object.
And this uvm_reg_cbs is a virtual class so we need to create a child class in order to instantiate it.
And in this child class we can override this post_predict() in order to declare some action that we want to be executed during this post_predict().
And the last missing puzzle of this definition is how we store this data and we can store this using another class part of the UVM library called uvm_callbacks.
And in this class there is this function called add() with which we will add references to instances of our callbacks.
So these are the elements with which we can implement register field callbacks.
So let's go again through this definition.
A callback is a function, so is this function post_predict() that is stored as data and we can store this function by creating an instance of this class and we store it using the add() function from this uvm_callbacks and designed to be called by another function.
So this one is called by this predict() function from uvm_reg_field.
And this is a very useful mechanism to have as it is quite common to need to trigger an action every time a register field is read or written.
And let's look closer at the signature of these two functions to see what arguments they have.
First, the post_predict().
It has these six arguments.
Field it's a pointer to the register field to which this callback is assigned.
Previous is the previous value of the register field and value is the current value which we want for example to write in the register field.
So this is the latest predicted value.
Kind tell us if the register is read or written so the possible values for kind are UVM_PREDICT_READ or UVM_PREDICT_WRITE.
The path argument will tell us if this access is a frontdoor access or backdoor access or so on, and map is a pointer to the register map.
And now let's look at this add() function.
First, let's discuss about the parameters of this uvm_callbacks class.
The first one, T, is the type of the object to which we want to add the callback.
So in our case is this uvm_reg_field as we want to add this callback to an uvm_reg_field instance.
The second one, CB, is the type of the callback that we want to add.
So in our case, it will be the class that we will extend from uvm_reg_cbs.
And let's look on the arguments of this add() function.
The first one, object, it's a pointer to the uvm_reg_field to which we want to add a callback.
The second one it's a pointer to the callback that we want to add, and the last one ordering control the order of the callbacks.
So this is useful when you add more than one callback to the same register field.
And now let's see an example of how we can use this register field callback.
So this is our Aligner with the 4 bytes on the RX MD interface and the 4 bytes on the MD TX interface.
We have here the Status register and the Control register.
We will use the callback mechanism to register a callback associated to this CLR register field from our Control register.
And what our callback will do is the following: Every time we write 1 to this CLR register it will reset our drop counter.
And this drop counter counts the number of illegal accesses detected on the MD RX interface.
So let's see a short animation to better understand this mechanism.
When we are receiving an illegal access on the MD RX interface, and remember that we are defining an illegal access, an access for which one of these two formulas is true.
So when this is happening, initially our drop counter is zero and when this access is received by the RTL, the RTL will drop this access and it will increment our drop counter and it will do the same for all the illegal accesses detected on the MD RX interface.
But this drop counter register field is read-only, so if we want to reset it back to 0, we need to write 1 in this CLR register field, and when this is happening, the drop counter is reset to 0.
So this is a perfect example to use this register field callback and let's see how we can do this.
The first thing that we need to do is to declare our register field callback class.
And we can call this clear count drop and it needs to extend from uvm_reg_cbs.
And in our callback class we need to override the post_predict() function and in this function we need to detect a write to the CLR register field.
And for this we can use the kind argument of the function.
So, whenever there is a write with value 1 in the CLR register field, we need to clear the drop counter.
So, we can use the predict() function of the uvm_reg_field class.
And, of course, in our callback function, we need to declare a pointer to this cnt_drop.
So, remember this value is the current predicted value, the mirror value of our register field to which we assigned this callback.
But if you look closely, this value argument is of type inout.
This means that we can change the mirrored value from our register field to whatever we want.
So, we can set back to zero our CLR register field after we cleared the drop counter.
So that's a pretty straightforward implementation for our callback.
And now let's see the logic with which we will register this callback to this CLR register field.
We can do this in the connect_phase() of our model class.
Here we will have to create an instance of this callback.
Then we will have to connect this cnt_drop pointer.
And finally we can add this callback using the add() function of the uvm_callbacks class and we can specify in the add() function call that we want to add this callback to this register field.
And that's all we have to do in order to add a register field callback.
Now let's look in the UVM documentation to see where you can find more information about the callback mechanism from UVM package.
First, the "Class Reference" manual.
Here, there are several chapters.
First, in the "Synchronization Classes" chapter, there is this section "uvm_callback".
And in here, you'll find the API of uvm_callbacks class and uvm_callback. uvm_callbacks has that add() function to add callbacks and uvm_callback is the base class for all the callback classes.
Another relevant chapter is in "Register Layer", "Register Model", "Callbacks".
And in here you'll find the API of this uvm_reg_cbs.
So that's the class which contains that post_predict() function that we talked about.
And in the "UVM User Guide" there is also a section under the "Advanced Topics", "Callbacks", and this chapter talks about the overall callbacks mechanism, not just the register field callback.
That's it for this tutorial.
We talked about the register field callback mechanism and we saw how we can declare a callback and how we can add a callback to a register field.
In the next tutorial, we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
