# Draw some conclusions regarding our UVM register model

*Chapter: Register model (RAL) · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to draw some conclusions regarding our UVM register model.
First of all, congratulations to you for completing this section of the tutorial.
And let's look again through all the things that you learned during this section.
First of all, you learn how to model a register using those classes: uvm_reg and uvm_reg_field.
Then you learn how to pack all those registers inside a register block.
And remember that an instance of a register block is called a register model.
Once we had the definition of that register block, we connected that register block to our bus monitor from the APB agent.
And once we did that we enable the checks on all the accesses to the registers on the APB interface.
But not only that we have checks for the data, we also have checks for the response returned by the RTL on the APB interface implemented in our custom register predictor.
After that, we connected our register block to the bus sequencer from the APB agent.
And that enabled us to write more generic tests.
Remember that once we did this we were able to replace those APB sequences from our tests with those tasks from the uvm_reg class: read(), write(), and update().
This action removed from our tests the information about the protocol used to access the registers.
And this is a big thing because maybe in the future the APB interface might be updated with something else and we will change the agent, but our tests will remain the same.
And the last thing that we learn is how to write a register field callback.
And we had a perfect scenario for a register field callback for that CLR register field from our Control register.
That's a lot of information to acquire regarding how the registers are modeled using the UVM library, and you should feel proud of yourself for having this knowledge.
And to get a better feeling of what you accomplished in this section, let's have a look at the image of our environment.
We now have our register model and the predictor sitting on top of the APB agent.
In our custom register predictor, we are verifying all the responses of the RTL to all the accesses on the APB interface.
Our register model gets updated for all the write accesses on the APB interface and it is also verifying that whenever there is a read access on the APB interface, the returned data by the RTL matches whatever our register model has in its mirrored values.
So, we already started to verify some of the functionality of the Aligner RTL.
And in the next section of our training we will model all the functionality of our Aligner and of course we will implement the rest of the components in our environment.
And before we close this section, there is one last thing to do.
In order to keep our EDA Playground project as clean as possible, I will copy the content of all these files, part of the register package, in here, in our register package file.
So this will give us more room in this section where we are coding our classes.
And just like before, I want to mention that this is something that you should not do in a real project.
In a real project, you should keep each class in its separate file like we have now.
And besides moving the classes of the register package here, I will also move the adapter inside the APB package all the way here at the end.
You don't have to do this on your own as this is not something that you should do in a real project, but just keep in mind that starting with the next practice project, you'll find all the registers and the register model here under the register package file.
That's it for this tutorial.
I hope everything was clear for you throughout this entire section.
Thanks for watching and see you in the next tutorial.
Bye!
